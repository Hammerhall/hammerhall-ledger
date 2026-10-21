# Статья 9 «Данные дальше: конвертеры JPA, JSON в столбце, выборки по времени, индексы» — утверждения статьи,
# которые проверяет прогон. Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 8: Postgres, JPA, Flyway, веб, охрана, Actuator, стенд, объекты-значения. Тесты статьи
# уже прошли в mvn verify (SeverityConverterTest, IncidentLogAgeTest, IncidentAgeIT, IncidentColumnsIT) — вместе
# с тестами статей 2–8: IncidentTableIT вставляет строку без новых столбцов, IncidentListIT сверяет JSON ручки.
# Здесь — лист сборки статьи (Hibernate 7 из BOM Boot 4.1, @JdbcTypeCode с Jackson 3, validate против jsonb,
# разбор имени метода, show-sql, Testcontainers) и то, что статья обещает словами: миграция на базе со строками,
# SQL и EXPLAIN на Postgres из docker run (как в статье 3а), тексты ошибок старта, свой маппер JSON у Hibernate,
# тест, который краснеет от ошибки в имени метода, занятое имя индекса.

JAR=target/game-day-0.0.1-SNAPSHOT.jar
DB=game-day-db
PASSWORD=game-day-local
PORT=${GAME_DAY_DB_PORT:-5432}
IMAGE=postgres:17-alpine
MAIN=src/main/java/example/gameday/journal
TEST=src/test/java/example/gameday/journal
MIGRATIONS=src/main/resources/db/migration
V1=$MIGRATIONS/V1__game_day_incident.sql
V2=$MIGRATIONS/V2__game_day_incident_severity.sql
APP_DB=postgres
APP_ENV=()
classpath >/dev/null
DEPS=$(cat target/cp.txt)

# Запрос из раздела EXPLAIN — буква в букву, как в статье.
PLAN_SQL="EXPLAIN SELECT id FROM game_day.incident
WHERE fixed_at IS NULL AND detected_at < '2026-10-05T09:30:00Z'
ORDER BY detected_at;"

# 200 000 учебных строк — как в статье, без комментариев в концах строк.
FILL_SQL="INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
SELECT 'учебное ' || n,
       TIMESTAMPTZ '2026-01-01 00:00:00Z' + n * INTERVAL '1 minute',
       CASE WHEN n % 200 = 0 THEN NULL
            ELSE TIMESTAMPTZ '2026-01-01 00:00:00Z' + n * INTERVAL '1 minute' + INTERVAL '5 minutes' END,
       'duty-1'
FROM generate_series(1, 200000) AS n;
ANALYZE game_day.incident;"

# База на минуту — команда статьи 3а; ждём, пока Postgres примет подключение по TCP.
db_up() {
    docker rm -f "$DB" >/dev/null 2>&1
    docker run -d --rm --name "$DB" -p "127.0.0.1:$PORT:5432" \
        -e POSTGRES_PASSWORD="$PASSWORD" "$IMAGE" >/dev/null || return 1
    local i
    for ((i = 0; i < 90; i++)); do
        docker exec "$DB" pg_isready -q -h 127.0.0.1 -U postgres && return 0
        sleep 1
    done
    return 1
}

db_down() { docker rm -f "$DB" >/dev/null 2>&1; return 0; }

# psql внутри контейнера; SQL — со стандартного ввода, как если бы его печатали после postgres=#. $1 — база.
psql_in() { docker exec -i "$DB" psql -X -U postgres -d "$1" 2>&1; }

# Одно значение без рамок таблицы. $1 — база, $2 — запрос.
psql_value() { docker exec "$DB" psql -X -U postgres -d "$1" -tA -c "$2" 2>&1; }

# Песочница, как в статье 5: адрес базы — переменными окружения (база — APP_DB, лишние переменные — APP_ENV).
# Веб не выключаем — охране нужен HttpSecurity; порт — любой свободный. Работает в фоне: ждём, пока main
# допишет «атакующих …», упадёт или выйдет, потом гасим. $1 — .jar или каталог классов варианта, дальше —
# аргументы приложения. Печатает лог; код 0 — main дошёл до конца.
app_run() {
    local what=$1 log pid i code=1
    shift
    local cmd=(java "${UTF8[@]}")
    if [[ $what == *.jar ]]; then
        cmd+=(-jar "$what")
    else
        cmd+=(-cp "$what:$DEPS" example.gameday.GameDayApplication)
    fi
    log=$(mktemp)
    env SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:$PORT/$APP_DB" \
        SPRING_DATASOURCE_USERNAME=postgres SPRING_DATASOURCE_PASSWORD="$PASSWORD" "${APP_ENV[@]}" \
        "${cmd[@]}" --server.port=0 "$@" >"$log" 2>&1 &
    pid=$!
    for ((i = 0; i < 180; i++)); do
        if grep -qE 'атакующих [0-9]' "$log"; then
            code=0
            break
        fi
        grep -qF 'Exception in thread "main"' "$log" && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    cat "$log"
    rm -f "$log"
    return "$code"
}

# Каталог с миграциями для варианта: копии файлов из src/main/resources/db/migration. Печатает путь.
migrations_dir() {
    local dir
    dir="$VARIANTS/$(basename "$PWD")-$1"
    shift
    rm -rf "$dir" && mkdir -p "$dir"
    cp "$@" "$dir/"
    echo "$dir"
}

# Классы варианта: копия target/classes, поверх — перекомпилированные исходники варианта (пути от его корня).
# Лог javac — в javac.log варианта; код — как у javac.
variant_classes() {
    local dir=$1
    shift
    rm -rf "$dir/classes" && cp -r target/classes "$dir/classes"
    (cd "$dir" && javac -encoding UTF-8 -proc:none -parameters -nowarn -d classes -cp "classes:$DEPS" "$@") \
        >"$dir/javac.log" 2>&1
}

# Тесты варианта: вывод Maven и отчёты Surefire — в mvn.log варианта; код — как у Maven.
variant_test() {
    local dir=$1 code
    shift
    (cd "$dir" && timeout 900 mvn -B -ntp test "$@" >mvn.log 2>&1); code=$?
    cat "$dir"/target/surefire-reports/*.txt >>"$dir/mvn.log" 2>/dev/null
    return "$code"
}

# Отчёт Surefire о классе: «тестов N, все зелёные». Аргументы: каталог, класс, N.
suite_ok() {
    local head
    head=$(grep -m 1 '<testsuite' "$1/target/surefire-reports/TEST-$2.xml" 2>/dev/null)
    if grep -q "tests=\"$3\"" <<<"$head" && grep -q 'failures="0"' <<<"$head" \
        && grep -q 'errors="0"' <<<"$head" && grep -q 'skipped="0"' <<<"$head"; then
        pass "$2: тестов $3, все зелёные"
    else
        fail "$2: ждали $3 зелёных — ${head:-отчёта нет}"
    fi
}

# Отчёт Surefire о классе: все тесты зелёные, сколько бы их ни было. Аргументы: каталог, класс.
suite_green() {
    local head
    head=$(grep -m 1 '<testsuite' "$1/target/surefire-reports/TEST-$2.xml" 2>/dev/null)
    if [ -n "$head" ] && grep -q 'failures="0"' <<<"$head" && grep -q 'errors="0"' <<<"$head"; then
        pass "$2 — зелёный"
    else
        fail "$2: ${head:-отчёта нет}"
    fi
}

# Исход каждого теста класса по отчёту Surefire: «имя ok» или «имя red». Аргументы: каталог, класс.
case_results() {
    python3 - "$1/target/surefire-reports/TEST-$2.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except (OSError, ET.ParseError):
    sys.exit(0)
for case in root.iter("testcase"):
    red = case.find("failure") is not None or case.find("error") is not None
    print(case.get("name"), "red" if red else "ok")
PY
}

# Строки лога с этим текстом — первая; для show.
first_line() { grep -m 1 -F -- "$1" <<<"$2"; }

trap db_down EXIT

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok . example.gameday.journal.SeverityConverterTest 1
suite_ok . example.gameday.journal.IncidentLogAgeTest 1
suite_ok . example.gameday.journal.IncidentAgeIT 1
suite_ok . example.gameday.journal.IncidentColumnsIT 2
for cls in IncidentTest IncidentTableIT IncidentRepositoryIT IncidentLogIT IncidentLogTest IncidentPagesIT \
    IncidentListServiceTest IncidentListIT; do
    suite_green . "example.gameday.journal.$cls"
done
suite_green . example.gameday.GameDayApplicationTests

section "Версии из BOM Boot 4.1: Hibernate 7, Jackson 3 — и нет Jackson 2"
mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp-test.txt -Dmdep.includeScope=test >/dev/null
jars=$(tr ':' '\n' <target/cp-test.txt | sed 's#.*/##')
expect_regex "$jars" '^hibernate-core-7\.[0-9]+\.[0-9]+' "статья: Hibernate 7 (JSON через @JdbcTypeCode с 6.0)"
expect_regex "$jars" '^jackson-databind-3\.' "Jackson 3 на пути классов — его и найдёт Hibernate"
expect_not_contains "$(grep -E '^jackson-databind-2\.' <<<"$jars")" "jackson-databind-2" \
    "Jackson 2 (com.fasterxml jackson-databind) нет: Hibernate не возьмёт его вместо Jackson 3"
note "$(grep -E '^(hibernate-core|jackson-databind|spring-data-jpa|postgresql|flyway-core)-' <<<"$jars" | tr '\n' ' ')"
note "$(java -version 2>&1 | head -n 1)"

section "Миграция на базе со строками: без V2 — сверка, без DEFAULT — contains null values, с DEFAULT — старт"
if db_up; then
    pass "docker run $IMAGE: база на минуту, как в статье 3а"
else
    fail "база в контейнере не поднялась"
fi
note "$(psql_value postgres 'SHOW server_version')"

dir=$(migrations_dir v1-only "$V1")
APP_ENV=(SPRING_FLYWAY_LOCATIONS="filesystem:$dir")
out=$(app_run "$JAR"); code=$?
APP_ENV=()
expect_failed "$code" "приложение статьи 9 на базе только с V1"
expect_contains "$out" 'Successfully applied 1 migration to schema "game_day", now at version v1' "Flyway применил V1"
expect_regex "$out" 'Schema validation: missing column \[(severity|details)\] in table \[game_day\.incident\]' \
    "поля без столбцов: Hibernate сверил сущность с таблицей и не дал подняться"
show "$(grep -m 1 -o 'Schema validation: missing column [^]]*] in table [^]]*]' <<<"$out")"

out=$(psql_in postgres <<'EOF'
INSERT INTO game_day.incident (title, detected_at, duty_name)
VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', 'duty-1');
ALTER TABLE game_day.incident ADD COLUMN severity VARCHAR(10) NOT NULL;
EOF
)
expect_contains "$out" 'ERROR:  column "severity" of relation "incident" contains null values' \
    "ADD COLUMN … NOT NULL на таблице со строкой — ошибка, как в статье"
show "$(first_line 'contains null values' "$out")"

dir=$(migrations_dir no-default "$V1" "$V2")
sed -i "s/NOT NULL DEFAULT 'low'/NOT NULL/" "$dir/$(basename "$V2")"
expect_not_contains "$(cat "$dir/$(basename "$V2")")" "DEFAULT 'low'" "в V2 варианта у severity нет DEFAULT"
APP_ENV=(SPRING_FLYWAY_LOCATIONS="filesystem:$dir")
out=$(app_run "$JAR"); code=$?
APP_ENV=()
expect_failed "$code" "приложение с V2 без DEFAULT на базе со строкой"
expect_contains "$out" 'column "severity" of relation "incident" contains null values' \
    "Flyway не применил миграцию, приложение не стартовало"
show "$(first_line 'contains null values' "$out")"

out=$(app_run "$JAR"); code=$?
expect_ok "$code" "приложение статьи 9 с V2 из .jar"
expect_contains "$out" 'Successfully applied 1 migration to schema "game_day", now at version v2' "Flyway применил V2"
show "$(first_line 'Successfully applied' "$out")"
out=$(psql_in postgres <<'EOF'
SELECT title, severity, details FROM game_day.incident ORDER BY detected_at;
EOF
)
expect_regex "$out" 'стенд не отвечает +\| low +\| \{\}' "старая строка получила DEFAULT: low и {}"
expect_regex "$out" 'Брокер не отвечает +\| low +\| \{\}' \
    "add(String) записал через Hibernate: LOW кодом low, пустые подробности — {} в jsonb"
show "$out"

section "JSONB: проверки таблицы, ->>, порядок ключей, varchar в jsonb, имя индекса"
out=$(psql_in postgres <<'EOF'
INSERT INTO game_day.incident (title, detected_at, duty_name, severity)
VALUES ('заглавными', '2026-10-05T09:15:00Z', 'duty-1', 'CRITICAL');
INSERT INTO game_day.incident (title, detected_at, duty_name, details)
VALUES ('массив', '2026-10-05T09:15:00Z', 'duty-1', '["broker"]');
INSERT INTO game_day.incident (title, detected_at, duty_name, details)
VALUES ('вложенный', '2026-10-05T09:15:00Z', 'duty-1', '{"target": {"host": "broker"}}');
INSERT INTO game_day.incident (title, detected_at, duty_name, details)
VALUES ('битый', '2026-10-05T09:15:00Z', 'duty-1', '{"target": "broker"');
INSERT INTO game_day.incident (title, detected_at, duty_name, details)
VALUES ('брокер молчит', '2026-10-05T09:15:00Z', 'duty-1', '{"target": "broker", "attacker": "teamlead"}');
SELECT 'вложенный: ' || count(*) FROM game_day.incident WHERE title = 'вложенный';
SELECT title FROM game_day.incident WHERE details ->> 'target' = 'broker';
SELECT '{"a":"1","b":"2"}'::jsonb = '{"b":"2","a":"1"}'::jsonb AS jsonb_equal,
       '{"a":"1","b":"2"}'::text = '{"b":"2","a":"1"}'::text AS text_equal;
PREPARE put_details(varchar) AS
    INSERT INTO game_day.incident (title, detected_at, duty_name, details)
    VALUES ('строкой', '2026-10-05T09:15:00Z', 'duty-1', $1);
CREATE TABLE game_day.other (id int);
CREATE INDEX ix_incident_open_detected ON game_day.other (id);
\d game_day.incident
EOF
)
expect_contains "$out" 'violates check constraint "incident_severity_known"' "CRITICAL заглавными база не пустила"
expect_contains "$out" 'violates check constraint "incident_details_object"' "массив [\"broker\"] база не пустила"
expect_contains "$out" "вложенный: 1" "вложенный объект {\"target\": {\"host\": …}} CHECK пропустил"
expect_contains "$out" 'ERROR:  invalid input syntax for type json' "битый JSON в jsonb не лёг"
expect_regex "$out" '^ брокер молчит$' "details ->> 'target' = 'broker' нашёл строку"
expect_regex "$out" '^ t +\| f$' "jsonb с другим порядком ключей равны, текст — нет"
expect_contains "$out" 'ERROR:  column "details" is of type jsonb but expression is of type character varying' \
    "varchar в jsonb Postgres сам не превращает"
expect_contains "$out" 'ERROR:  relation "ix_incident_open_detected" already exists' \
    "имя индекса уникально во всей схеме, не только в таблице"
expect_contains "$out" '"ix_incident_open_detected" btree (detected_at) WHERE fixed_at IS NULL' \
    "индекс по умолчанию — B-tree, частичный"
show "$(grep -E '^ERROR:' <<<"$out")"
show "$(grep -E 'Index|btree|Check|CHECK' <<<"$out")"

section "EXPLAIN на свежей базе: как в статье — Flyway, маленькая таблица, 200 000 строк, план"
psql_value postgres "CREATE DATABASE fresh" >/dev/null
APP_DB=fresh
out=$(app_run "$JAR"); code=$?
APP_DB=postgres
expect_ok "$code" "java -jar на свежей базе"
expect_contains "$out" 'Successfully applied 2 migrations to schema "game_day", now at version v2' \
    "строка Flyway — как в статье"
show "$(first_line 'Successfully applied' "$out")"

out=$(printf '%s\n' "ANALYZE game_day.incident;" "$PLAN_SQL" | psql_in fresh)
expect_contains "$out" "Seq Scan on incident" "таблица из одной строки, посчитанная ANALYZE, — Seq Scan даже с индексом"
expect_contains "$out" "Sort" "…и над ним Sort: сортировала сама"
show "$out"

out=$(printf '%s\n' "$FILL_SQL" "$PLAN_SQL" | psql_in fresh)
expect_contains "$out" "INSERT 0 200000" "вставлено 200 000 учебных строк, CHECK миграции их пропустили"
expect_contains "$out" "Index Scan using ix_incident_open_detected on incident" "план статьи — Index Scan по частичному индексу"
expect_contains "$out" "Index Cond: (detected_at < '2026-10-05 09:30:00+00'::timestamp with time zone)" "Index Cond — как в статье"
expect_not_contains "$out" "Sort" "у Index Scan сортировки нет"
show "$(grep -E 'Index Scan|Index Cond' <<<"$out" | sed 's/^ *//')"

out=$(psql_in fresh <<'EOF'
SELECT count(*) FILTER (WHERE fixed_at IS NULL) AS open, count(*) AS total,
       count(*) FILTER (WHERE severity = 'low' AND details = '{}') AS by_default
FROM game_day.incident;
EOF
)
expect_regex "$out" '^ +1001 +\| +200001 +\| +200001$' \
    "открыта каждая 200-я (и «Брокер» от запуска); severity и details у всех — из DEFAULT"
show "$out"

out=$(psql_in fresh <<'EOF'
EXPLAIN SELECT id FROM game_day.incident
WHERE detected_at < '2026-10-05T09:30:00Z'
ORDER BY detected_at;
EOF
)
expect_contains "$out" "Seq Scan on incident" "без fixed_at IS NULL — Seq Scan…"
expect_contains "$out" "Sort" "…и Sort над ним"
expect_not_contains "$out" "ix_incident_open_detected" "частичный индекс база не взяла"
show "$(grep -E 'Scan|Sort|Filter' <<<"$out" | sed 's/^ *//')"

out=$(psql_in fresh <<'EOF'
SET plan_cache_mode = force_generic_plan;
PREPARE open_before(timestamptz) AS
    SELECT id FROM game_day.incident WHERE fixed_at IS NULL AND detected_at < $1 ORDER BY detected_at;
EXPLAIN EXECUTE open_before('2026-10-05T09:30:00Z');
EOF
)
expect_contains "$out" "Index Scan using ix_incident_open_detected on incident" \
    "граница параметром, как шлёт Hibernate, — тоже частичный индекс"
expect_contains "$out" 'Index Cond: (detected_at < $1)' "общий план: Index Cond с параметром"
show "$(grep -E 'Scan|Cond' <<<"$out" | sed 's/^ *//')"

out=$(psql_in fresh <<'EOF'
BEGIN;
CREATE INDEX ix_incident_detected ON game_day.incident (detected_at);
SELECT pg_size_pretty(pg_relation_size('game_day.ix_incident_open_detected')) AS partial,
       pg_size_pretty(pg_relation_size('game_day.ix_incident_detected')) AS full_index,
       pg_relation_size('game_day.ix_incident_detected') / pg_relation_size('game_day.ix_incident_open_detected') AS ratio;
ROLLBACK;
EOF
)
expect_regex "$out" '^ 40 kB +\| ' "частичный индекс — 40 КБ, как в статье"
ratio=$(awk -F'|' '/kB/ {gsub(/ /, "", $3); print $3}' <<<"$out" | head -n 1)
if [ "${ratio:-0}" -ge 100 ] 2>/dev/null; then
    pass "обычный по detected_at больше частичного в $ratio раз — «в сто с лишним»"
else
    fail "обычный индекс больше частичного в ${ratio:-?} раз, а статья говорит «в сто с лишним»"
fi
show "$out"

out=$(psql_in fresh <<'EOF'
BEGIN;
DROP INDEX game_day.ix_incident_open_detected;
CREATE INDEX ix_incident_duty_detected ON game_day.incident (duty_name, detected_at);
ANALYZE game_day.incident;
\echo === наша выборка
EXPLAIN SELECT id FROM game_day.incident
WHERE fixed_at IS NULL AND detected_at < '2026-10-05T09:30:00Z'
ORDER BY detected_at;
\echo === с дежурным
EXPLAIN SELECT id FROM game_day.incident
WHERE duty_name = 'duty-2' AND detected_at < '2026-10-05T09:30:00Z'
ORDER BY detected_at;
ROLLBACK;
EOF
)
ours=$(sed -n '/=== наша выборка/,/=== с дежурным/p' <<<"$out")
with_duty=$(sed -n '/=== с дежурным/,$p' <<<"$out")
expect_contains "$ours" "Seq Scan on incident" "составной (duty_name, detected_at) нашей выборке не помог — Seq Scan"
expect_not_contains "$ours" "ix_incident_duty_detected" "…индекс не тронут"
expect_regex "$with_duty" "(Index|Bitmap Index) Scan (using|on) ix_incident_duty_detected" \
    "с duty_name = … тот же индекс работает: «всех Ивановых найти быстро»"
show "$(grep -E '===|Scan|Cond|Filter|Sort' <<<"$out" | sed 's/^ *//')"

section "⚠️ Забытый OrderBy: без статистики база идёт по индексу — и порядок приходит сам"
psql_value postgres "CREATE DATABASE nostats" >/dev/null
out=$( { echo "CREATE SCHEMA game_day;"; cat "$V1" "$V2"; cat <<'EOF'
INSERT INTO game_day.incident (title, detected_at, duty_name) VALUES ('брокер молчит', '2026-10-05T09:20:00Z', 'duty-1');
INSERT INTO game_day.incident (title, detected_at, duty_name) VALUES ('лента стоит', '2026-10-05T09:50:00Z', 'duty-2');
INSERT INTO game_day.incident (title, detected_at, duty_name) VALUES ('письма копятся', '2026-10-05T09:30:00Z', 'duty-1');
INSERT INTO game_day.incident (title, detected_at, duty_name) VALUES ('диск заполнен', '2026-10-05T09:10:00Z', 'duty-2');
PREPARE no_order(timestamptz) AS
    SELECT title FROM game_day.incident WHERE fixed_at IS NULL AND detected_at < $1;
\echo === без статистики
EXPLAIN EXECUTE no_order('2026-10-05T09:30:00Z');
EXECUTE no_order('2026-10-05T09:30:00Z');
ANALYZE game_day.incident;
\echo === после ANALYZE
EXPLAIN EXECUTE no_order('2026-10-05T09:30:00Z');
EXECUTE no_order('2026-10-05T09:30:00Z');
EOF
} | psql_in nostats)
before=$(sed -n '/=== без статистики/,/=== после ANALYZE/p' <<<"$out")
after=$(sed -n '/=== после ANALYZE/,$p' <<<"$out")
expect_contains "$before" "Index Scan using ix_incident_open_detected" "таблица без статистики: база пошла по частичному индексу"
expect_regex "$(grep -E '^ (диск|брокер)' <<<"$before" | tr -d '\n')" '^ диск заполнен брокер молчит$' \
    "…и строки пришли по времени без ORDER BY — забытый OrderBy тест не поймал бы"
expect_contains "$after" "Seq Scan on incident" "после ANALYZE — Seq Scan"
expect_regex "$(grep -E '^ (диск|брокер)' <<<"$after" | tr -d '\n')" '^ брокер молчит диск заполнен$' \
    "…и порядок — как легли строки: план сменился, порядок вместе с ним"
show "$out"

section "Hibernate в тестах: show-sql, @Query, тест краснеет от ошибки в имени, свой маппер JSON"
v=$(make_variant claims)
sed -i -e 's/^import org.springframework.context.annotation.Import;$/&\nimport org.springframework.test.context.TestPropertySource;/' \
    -e 's/^class IncidentAgeIT {$/@TestPropertySource(properties = "spring.jpa.show-sql=true")\n&/' "$v/$TEST/IncidentAgeIT.java"
expect_contains "$(cat "$v/$TEST/IncidentAgeIT.java")" '@TestPropertySource(properties = "spring.jpa.show-sql=true")' \
    "над IncidentAgeIT — @TestPropertySource из статьи"
sed -i '$d' "$v/$MAIN/IncidentRepository.java"
cat >>"$v/$MAIN/IncidentRepository.java" <<'EOF'

    // Только для проверки прогона: тот же запрос в @Query — и имена с одной ошибкой каждое.
    @Query("select i from Incident i where i.fixedAt is null and i.detectedAt < ?1 order by i.detectedAt")
    List<Incident> findOpenDetectedBefore(Instant border);

    List<Incident> findByDetectedAtBeforeOrderByDetectedAtAsc(Instant border);

    List<Incident> findByFixedAtIsNullAndDetectedAtLessThanEqualOrderByDetectedAtAsc(Instant border);

    List<Incident> findByFixedAtIsNullAndDetectedAtBefore(Instant border);

    List<Incident> findByFixedAtIsNullOrderByDetectedAtAsc();
}
EOF
cat >"$v/$TEST/MutantAgeIT.java" <<'EOF'
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Instant;
import java.util.List;
import java.util.function.Function;

import static org.assertj.core.api.Assertions.assertThat;

/** Проверка прогона к статье 9: данные IncidentAgeIT ловят ошибку в имени метода. В статью не идёт. */
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class MutantAgeIT {

    private static final Instant BORDER = Instant.parse("2026-10-05T09:30:00Z");

    @Autowired
    private IncidentRepository incidents;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void emptyTable() {
        jdbc.execute("TRUNCATE game_day.incident");          // строки лягут на диск в порядке вставки
    }

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    // Данные и проверка — как в IncidentAgeIT; выборку подставляет тест.
    private void check(Function<Instant, List<Incident>> query, boolean analyze) {
        Incident broker = incidents.save(new Incident("брокер молчит", BORDER.minusSeconds(600), "duty-1"));
        incidents.save(new Incident("лента стоит", BORDER.plusSeconds(1200), "duty-2"));
        incidents.save(new Incident("письма копятся", BORDER, "duty-1"));
        Incident disk = incidents.save(new Incident("диск заполнен", BORDER.minusSeconds(1200), "duty-2"));
        Incident fixed = new Incident("стенд не отвечает", BORDER.minusSeconds(1800), "duty-1");
        fixed.fix(BORDER.minusSeconds(1500));
        incidents.save(fixed);
        if (analyze) {
            jdbc.execute("ANALYZE game_day.incident");       // база посчитала строки — маленькую таблицу читает целиком
        }

        assertThat(query.apply(BORDER))
                .extracting(Incident::getId)
                .containsExactly(disk.getId(), broker.getId());
    }

    @Test
    void queryAnnotation() {
        check(border -> incidents.findOpenDetectedBefore(border), false);
    }

    @Test
    void withoutIsNull() {
        check(border -> incidents.findByDetectedAtBeforeOrderByDetectedAtAsc(border), false);
    }

    @Test
    void lessThanEqual() {
        check(border -> incidents.findByFixedAtIsNullAndDetectedAtLessThanEqualOrderByDetectedAtAsc(border), false);
    }

    @Test
    void withoutTime() {
        check(border -> incidents.findByFixedAtIsNullOrderByDetectedAtAsc(), false);
    }

    @Test
    void withoutOrderByAfterAnalyze() {
        check(border -> incidents.findByFixedAtIsNullAndDetectedAtBefore(border), true);
    }
}
EOF
cat >"$v/$TEST/ArticleClaimsIT.java" <<'EOF'
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.json.JsonMapper;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;

/** Проверки прогона к статье 9: что статья говорит словами о JSON в столбце и преобразователе. В статью не идёт. */
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class ArticleClaimsIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private EntityManagerFactory entityManagerFactory;

    @Autowired
    private JsonMapper bootMapper;

    @AfterEach
    void cleanUp() {
        jdbc.update("DELETE FROM game_day.incident");
    }

    private static String chain(Throwable thrown) {
        StringBuilder text = new StringBuilder();
        for (Throwable t = thrown; t != null; t = t.getCause()) {
            String message = String.valueOf(t.getMessage()).lines().findFirst().orElse("");
            text.append(t.getClass().getName()).append(": ").append(message).append('\n');
        }
        return text.toString();
    }

    @Test
    void hibernateHasItsOwnStricterMapper() throws Exception {
        Object formatMapper = entityManagerFactory.unwrap(SessionFactory.class)
                .getSessionFactoryOptions().getJsonFormatMapper();
        System.out.println("CLAIM format mapper: " + formatMapper.getClass().getName());
        Field field = formatMapper.getClass().getDeclaredField("jsonMapper");
        field.setAccessible(true);
        JsonMapper hibernateMapper = (JsonMapper) field.get(formatMapper);
        boolean hibernateStrict = hibernateMapper.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
        boolean bootStrict = bootMapper.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
        System.out.println("CLAIM unknown property fails: hibernate " + hibernateStrict + ", boot bean " + bootStrict
                + ", same object " + (hibernateMapper == bootMapper));

        assertThat(formatMapper.getClass().getSimpleName()).isEqualTo("Jackson3JsonFormatMapper");
        assertThat(hibernateStrict).isTrue();
        assertThat(bootStrict).isFalse();
        assertThat(hibernateMapper).isNotSameAs(bootMapper);
    }

    @Test
    void nestedObjectPassesCheckButBreaksTheRow() {
        UUID id = UUID.randomUUID();
        int inserted = jdbc.update("""
                INSERT INTO game_day.incident (id, title, detected_at, duty_name, details)
                VALUES (?, 'брокер молчит', '2026-10-05T09:15:00Z', 'duty-1', '{"target": {"host": "broker"}}')
                """, id);

        Throwable byId = catchThrowable(() -> incidents.findById(id));
        Throwable all = catchThrowable(() -> incidents.findAll());

        System.out.print("CLAIM nested findById:\n" + chain(byId));
        System.out.print("CLAIM nested findAll:\n" + chain(all));
        assertThat(inserted).isEqualTo(1);
        assertThat(chain(byId)).contains("Cannot deserialize value of type `java.lang.String` from Object value");
        assertThat(all).isNotNull();
    }

    @Test
    void mapFromDatabaseIsMutableGetterIsNot() throws Exception {
        UUID id = incidents.save(new Incident("брокер молчит", T0, "duty-1",
                Severity.HIGH, Map.of("target", "broker"))).getId();
        Incident read = incidents.findById(id).orElseThrow();
        Field field = Incident.class.getDeclaredField("details");
        field.setAccessible(true);
        @SuppressWarnings("unchecked")
        Map<String, String> raw = (Map<String, String>) field.get(read);
        System.out.println("CLAIM details after read: " + raw.getClass().getName());

        raw.put("attacker", "teamlead");

        assertThat(raw).containsEntry("attacker", "teamlead");
        assertThatThrownBy(() -> read.getDetails().put("x", "y")).isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    void converterPassesNullAndRejectsUnknownCode() {
        SeverityConverter converter = new SeverityConverter();

        assertThat(converter.convertToDatabaseColumn(null)).isNull();
        assertThat(converter.convertToEntityAttribute(null)).isNull();
        assertThatThrownBy(() -> converter.convertToEntityAttribute("medium"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("незнакомая серьёзность");
    }

    @Test
    void oldConstructorAndSqlInsertGiveLowAndEmptyObject() {
        UUID viaJpa = incidents.save(new Incident("стенд не отвечает", T0, "duty-1")).getId();
        jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, duty_name)
                VALUES ('как IncidentTableIT', '2026-10-05T09:15:00Z', 'duty-1')
                """);

        assertThat(jdbc.queryForObject("SELECT severity || ' ' || details::text FROM game_day.incident WHERE id = ?",
                String.class, viaJpa)).isEqualTo("low {}");
        assertThat(jdbc.queryForObject("""
                SELECT severity || ' ' || details::text FROM game_day.incident WHERE title = 'как IncidentTableIT'
                """, String.class)).isEqualTo("low {}");
    }
}
EOF
variant_test "$v" -Dtest='IncidentAgeIT,ArticleClaimsIT,MutantAgeIT'
out=$(cat "$v/mvn.log")
suite_ok "$v" example.gameday.journal.IncidentAgeIT 1
suite_ok "$v" example.gameday.journal.ArticleClaimsIT 5
head=$(grep -s -m 1 '<testsuite' "$v/target/surefire-reports/TEST-example.gameday.journal.ArticleClaimsIT.xml")
if ! { grep -q 'failures="0"' <<<"$head" && grep -q 'errors="0"' <<<"$head"; }; then
    show "$(grep -E 'Tests run:|FAIL|ERROR|expected|Expect|CLAIM' <<<"$out" | head -n 40)"
fi

select_line=$(grep -m 1 -E '^Hibernate: select .*fixed_at is null' <<<"$out")
expect_contains "$select_line" "fixed_at is null" "show-sql: в WHERE есть fixed_at is null — частичному индексу этого и надо"
expect_regex "$select_line" 'detected_at ?< ?\?' "show-sql: detected_at<? — граница параметром, Before — строго меньше"
expect_regex "$select_line" 'order by [a-z0-9_]+\.detected_at' "show-sql: order by detected_at"
show "$select_line"
insert_line=$(grep -m 1 -E '^Hibernate: insert into game_day\.incident' <<<"$out")
expect_contains "$insert_line" "severity" "show-sql: Hibernate пишет severity в каждый insert — умолчание базы ему не нужно"
expect_contains "$insert_line" "details" "show-sql: …и details"
show "$insert_line"

results=$(case_results "$v" example.gameday.journal.MutantAgeIT)
expect_contains "$results" "queryAnnotation ok" "тот же запрос в @Query даёт тот же ответ"
for mutant in withoutIsNull lessThanEqual withoutTime withoutOrderByAfterAnalyze; do
    expect_contains "$results" "$mutant red" "данные IncidentAgeIT ловят ошибку: $mutant"
done
show "$results"

expect_contains "$out" "CLAIM format mapper: org.hibernate.type.format.jackson.Jackson3JsonFormatMapper" \
    "Hibernate нашёл Jackson 3 сам"
expect_contains "$out" "CLAIM unknown property fails: hibernate true, boot bean false, same object false" \
    "маппер Hibernate свой и строже бина Boot: незнакомое поле — ошибка"
expect_contains "$out" 'Cannot deserialize value of type `java.lang.String` from Object value' \
    "вложенный объект: CHECK пропустил, а строка не читается — текст Jackson, как в статье"
show "$(grep -E '^CLAIM|^(org|tools|java|jakarta)\.[^ ]+: ' <<<"$out" | head -n 20)"

section "Перечисление: без аннотации — номер, STRING — имя, @Enumerated вместе с @Convert — не стартует"
v=$(make_variant ordinal)
sed -i '/^    @Convert(converter = SeverityConverter.class)$/d' "$v/$MAIN/Incident.java"
expect_not_contains "$(cat "$v/$MAIN/Incident.java")" "@Convert(converter = SeverityConverter.class)" "у поля severity нет ни @Enumerated, ни @Convert"
if variant_classes "$v" "$MAIN/Incident.java"; then
    out=$(app_run "$v/classes"); code=$?
    expect_failed "$code" "приложение с перечислением без аннотации"
    expect_contains "$out" "wrong column type encountered in column [severity]" "сверка validate поймала: в столбце строка"
    expect_regex "$out" 'column \[severity\].*expecting \[(smallint|tinyint)' "Hibernate ждёт номер — ORDINAL по умолчанию"
    show "$(grep -m 1 -o 'Schema validation: wrong column type encountered in column \[severity\].*' <<<"$out")"
else
    fail "вариант ordinal не скомпилировался"
    show "$(cat "$v/javac.log")"
fi

v=$(make_variant enum-string)
sed -i 's/^    @Convert(converter = SeverityConverter.class)$/    @jakarta.persistence.Enumerated(jakarta.persistence.EnumType.STRING)/' "$v/$MAIN/Incident.java"
expect_contains "$(cat "$v/$MAIN/Incident.java")" "@jakarta.persistence.Enumerated(jakarta.persistence.EnumType.STRING)" \
    "вместо @Convert — @Enumerated(EnumType.STRING)"
if variant_classes "$v" "$MAIN/Incident.java"; then
    out=$(app_run "$v/classes"); code=$?
    expect_failed "$code" "запись происшествия с EnumType.STRING"
    expect_contains "$out" 'violates check constraint "incident_severity_known"' "имя LOW заглавными CHECK базы не пустил"
    expect_regex "$out" 'Failing row contains \(.*, LOW, \{\}\)' "в базу пошло имя константы, LOW"
    show "$(grep -m 1 -o 'ERROR: new row for relation "incident" violates check constraint "incident_severity_known"' <<<"$out")"
    show "$(grep -m 1 -o 'Failing row contains (.*)' <<<"$out")"
else
    fail "вариант enum-string не скомпилировался"
    show "$(cat "$v/javac.log")"
fi

v=$(make_variant enumerated-and-convert)
sed -i 's/^    @Convert(converter = SeverityConverter.class)$/    @jakarta.persistence.Enumerated(jakarta.persistence.EnumType.STRING)\n&/' "$v/$MAIN/Incident.java"
expect_contains "$(grep -A 1 '@jakarta.persistence.Enumerated' "$v/$MAIN/Incident.java")" "@Convert(converter = SeverityConverter.class)" \
    "над полем и @Enumerated, и @Convert"
if variant_classes "$v" "$MAIN/Incident.java"; then
    out=$(app_run "$v/classes"); code=$?
    expect_failed "$code" "приложение с @Enumerated и @Convert на одном поле"
    expect_contains "$out" "'AttributeConverter' not allowed for attribute 'severity' annotated '@jakarta.persistence.Enumerated'" \
        "текст Hibernate — как в статье"
    show "$(grep -m 1 -o "'AttributeConverter' not allowed for attribute 'severity' annotated '@jakarta.persistence.Enumerated'" <<<"$out")"
else
    fail "вариант enumerated-and-convert не скомпилировался"
    show "$(cat "$v/javac.log")"
fi

section "JSON в jsonb через преобразователь-строку: validate не пускает, без сверки падает запись"
v=$(make_variant json-as-text)
cat >"$v/$MAIN/DetailsTextConverter.java" <<'EOF'
package example.gameday.journal;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.util.Map;
import java.util.TreeMap;

// Только для проверки прогона: способ 1 из части 2 — JSON строкой через преобразователь с Jackson.
@Converter
public class DetailsTextConverter implements AttributeConverter<Map<String, String>, String> {

    private static final JsonMapper MAPPER = JsonMapper.builder().build();

    @Override
    public String convertToDatabaseColumn(Map<String, String> details) {
        return details == null ? null : MAPPER.writeValueAsString(new TreeMap<>(details));
    }

    @Override
    public Map<String, String> convertToEntityAttribute(String json) {
        return json == null ? null : MAPPER.readValue(json, new TypeReference<Map<String, String>>() { });
    }
}
EOF
sed -i 's/^    @JdbcTypeCode(SqlTypes.JSON)$/    @Convert(converter = DetailsTextConverter.class)/' "$v/$MAIN/Incident.java"
expect_contains "$(cat "$v/$MAIN/Incident.java")" "@Convert(converter = DetailsTextConverter.class)" \
    "у details — преобразователь в строку вместо @JdbcTypeCode"
if variant_classes "$v" "$MAIN/Incident.java" "$MAIN/DetailsTextConverter.java"; then
    out=$(app_run "$v/classes"); code=$?
    expect_failed "$code" "приложение с преобразователем-строкой на столбце jsonb"
    expect_contains "$out" "Schema validation: wrong column type encountered in column [details] in table [game_day.incident]; found [jsonb (Types#OTHER)], but expecting [varchar(255) (Types#VARCHAR)]" \
        "текст сверки — как в статье"
    show "$(grep -m 1 -o 'Schema validation: wrong column type encountered in column \[details\].*' <<<"$out")"
    out=$(app_run "$v/classes" --spring.jpa.hibernate.ddl-auto=none); code=$?
    expect_failed "$code" "без сверки (ddl-auto: none) — первая запись"
    expect_contains "$out" 'ERROR: column "details" is of type jsonb but expression is of type character varying' \
        "строку Hibernate отдал как varchar — текст Postgres, как в статье"
    show "$(grep -m 1 -o 'ERROR: column "details" is of type jsonb but expression is of type character varying' <<<"$out")"
else
    fail "вариант json-as-text не скомпилировался"
    show "$(cat "$v/javac.log")"
fi

section "⚠️ V2 без DEFAULT: на пустой базе тестов миграция проходит, а IncidentTableIT краснеет"
v=$(make_variant no-default-tests)
sed -i "s/NOT NULL DEFAULT 'low'/NOT NULL/" "$v/$V2"
variant_test "$v" -Dtest='IncidentAgeIT,IncidentTableIT'; code=$?
out=$(cat "$v/mvn.log")
expect_failed "$code" "mvn test с V2 без DEFAULT"
suite_ok "$v" example.gameday.journal.IncidentAgeIT 1
expect_contains "$(case_results "$v" example.gameday.journal.IncidentTableIT)" "acceptsOpenIncident red" \
    "IncidentTableIT: вставка без severity — красная"
expect_contains "$out" 'null value in column "severity"' "текст Postgres: severity пустой, а NOT NULL пустого не пускает"
show "$(grep -m 1 -o 'null value in column "severity"[^;]*' <<<"$out")"

section "⚠️ Занятое имя индекса: Flyway падает, причина — только в первом падении"
v=$(make_variant duplicate-index)
cat >"$v/$MIGRATIONS/V3__game_day_incident_title.sql" <<'EOF'
-- src/main/resources/db/migration/V3__game_day_incident_title.sql
CREATE INDEX ix_incident_open_detected ON game_day.incident (title);
EOF
variant_test "$v" -Dtest='IncidentAgeIT,IncidentColumnsIT,IncidentTableIT'; code=$?
out=$(cat "$v/mvn.log")
expect_failed "$code" "mvn test с V3, где имя индекса занято"
expect_contains "$out" 'relation "ix_incident_open_detected" already exists' "в первом падении — причина"
expect_contains "$out" "ApplicationContext failure threshold (1) exceeded" \
    "дальше Spring приложение не поднимает — текст, как в статье"
show "$(grep -m 1 -o 'ERROR: relation "ix_incident_open_detected" already exists' <<<"$out")"
show "$(grep -m 1 -o 'ApplicationContext failure threshold (1) exceeded.\{0,40\}' <<<"$out")"
note "тестов с ошибкой контекста: $(grep -c 'failure threshold (1) exceeded' "$v"/target/surefire-reports/*.txt 2>/dev/null | awk -F: '{s += $2} END {print s + 0}')"

# Убрать базу статьи, если что-то оборвалось раньше; последняя команда — с кодом 0.
db_down
