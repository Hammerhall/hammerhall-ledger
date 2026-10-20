# Статья 3а «Данные, часть 1: таблица и миграция» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Тесты статьи уже прошли в mvn verify: IncidentTableIT на Postgres из Testcontainers
# (в том числе: текст DataIntegrityViolationException содержит имя проверки),
# GameDayApplicationTests с @Import. Здесь — что статья обещает словами:
# psql в контейнере, лог и история Flyway, ошибки при правке миграции, без стартера,
# без @Import, без Docker; Ryuk в docker ps.

JAR=target/game-day-0.0.1-SNAPSHOT.jar
DB=game-day-db
PASSWORD=game-day-local
PORT=${GAME_DAY_DB_PORT:-5432}
IMAGE=postgres:17-alpine
MIGRATION=src/main/resources/db/migration/V1__game_day_incident.sql
NOTE_LINE='    note         VARCHAR(500)  NULL,'

# База на минуту — команда статьи (часть 1); ждём, пока Postgres примет подключение по TCP.
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

# psql внутри контейнера; SQL — со стандартного ввода, как если бы его печатали после postgres=#.
psql_in() { docker exec -i "$DB" psql -X -U postgres -d "${1:-postgres}" 2>&1; }

# Одно значение без рамок таблицы.
psql_value() { docker exec "$DB" psql -X -U postgres -d "$1" -tA -c "$2" 2>&1; }

# Приложение из части 2: адрес базы — переменными окружения, как в статье.
# Второй аргумент — каталог с миграциями вместо тех, что в .jar (для «что будет, если…»).
app() {
    local database=$1 locations=${2:-}
    local env=(SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:$PORT/$database"
        SPRING_DATASOURCE_USERNAME=postgres SPRING_DATASOURCE_PASSWORD="$PASSWORD")
    [ -n "$locations" ] && env+=(SPRING_FLYWAY_LOCATIONS="filesystem:$locations")
    env "${env[@]}" timeout 180 java "${UTF8[@]}" -jar "$JAR" 2>&1
}

# Каталог с миграциями для варианта: копия нашей V1 (её имя — первым аргументом).
migrations_dir() {
    local dir
    dir="$VARIANTS/$(basename "$PWD")-$1"
    rm -rf "$dir" && mkdir -p "$dir"
    cp "$MIGRATION" "$dir/$2"
    echo "$dir"
}

# Запущенные контейнеры Testcontainers: Postgres статьи и уборщик Ryuk — «образ id».
tc_containers() { docker ps --format '{{.Image}} {{.ID}}' | grep -E "^($IMAGE|testcontainers/ryuk[^ ]*) "; }
tc_images() { tc_containers | cut -d ' ' -f 1; }

wait_tc_gone() {
    local i
    for ((i = 0; i < 60; i++)); do
        [ -z "$(tc_images)" ] && return 0
        sleep 1
    done
    return 1
}

trap db_down EXIT

section "Часть 1: Postgres на минуту — docker run и psql в контейнере"
if db_up; then
    pass "docker run $IMAGE: база принимает подключения на 127.0.0.1:$PORT"
else
    fail "база в контейнере не поднялась"
fi
out=$( { echo "CREATE SCHEMA game_day;"; cat "$MIGRATION"; cat <<'EOF'
INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', '2026-10-05T09:14:00Z', 'duty-1');
INSERT INTO game_day.incident (title, detected_at, duty_name)
VALUES ('   ', '2026-10-05T09:15:00Z', 'duty-1');
INSERT INTO game_day.incident (title, detected_at, duty_name)
VALUES (repeat('x', 201), '2026-10-05T09:15:00Z', 'duty-1');
INSERT INTO game_day.incident (title, detected_at, duty_name)
VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', 'duty-1');

SET TIME ZONE 'UTC';
SELECT detected_at FROM game_day.incident;

SET TIME ZONE 'Europe/Moscow';
SELECT detected_at FROM game_day.incident;
EOF
} | psql_in)
expect_contains "$out" 'ERROR:  new row for relation "incident" violates check constraint "incident_fixed_after_detected"' \
    "починили раньше, чем заметили — ошибка с именем проверки, как в статье"
show "$(grep -m 1 'incident_fixed_after_detected' <<<"$out")"
expect_contains "$out" 'violates check constraint "incident_title_check"' "заголовок из одних пробелов не прошёл (btrim)"
expect_contains "$out" 'value too long for type character varying(200)' "заголовок длиннее 200 знаков не прошёл"
expect_contains "$out" ' 2026-10-05 09:15:00+00' "SET TIME ZONE 'UTC' — 09:15:00+00"
expect_contains "$out" ' 2026-10-05 12:15:00+03' "SET TIME ZONE 'Europe/Moscow' — 12:15:00+03"
show "$(grep -E '^ 2026-10-05' <<<"$out")"

docker stop "$DB" >/dev/null 2>&1
gone=1
for _ in $(seq 15); do
    [ -z "$(docker ps -aq --filter "name=^${DB}\$")" ] && { gone=0; break; }
    sleep 1
done
if [ "$gone" -eq 0 ]; then pass "docker stop: с --rm контейнер удалён вместе с базой"; else fail "после docker stop контейнер $DB остался"; fi

section "Часть 2: без адреса базы приложение не стартует"
out=$(timeout 180 java "${UTF8[@]}" -jar "$JAR" 2>&1); code=$?
expect_failed "$code" "java -jar без SPRING_DATASOURCE_*"
expect_contains "$out" "Failed to configure a DataSource" "текст ошибки — как в статье"
show "$(grep -m 1 'Failed to configure a DataSource' <<<"$out")"

section "Часть 2: первый запуск — Flyway создаёт схему и применяет V1"
db_up || fail "база в контейнере не поднялась"
out=$(app postgres); code=$?
expect_ok "$code" "java -jar с SPRING_DATASOURCE_*"
expect_contains "$out" 'Successfully applied 1 migration to schema "game_day", now at version v1' "строка Flyway в логе"
expect_contains "$out" "[оповещение] duty-1: Брокер не отвечает" "журнал из статьи 2 на месте"
expect_contains "$out" "игра PT3H, атакующих 2" "настройки из статьи 2 на месте"
show "$(grep -E 'Successfully applied|\[оповещение\]|игра PT' <<<"$out")"

out=$(printf '%s\n' "SELECT version, description, checksum" "FROM game_day.flyway_schema_history" \
    "ORDER BY installed_rank;" | psql_in)
expect_contains "$out" "<< Flyway Schema Creation >>" "первая строка истории — пометка: схему создал Flyway"
expect_contains "$out" "game day incident" "описание миграции — из имени файла"
expect_contains "$out" "280339142" "контрольная сумма V1 — как в статье"
show "$out"
expect_contains "$(psql_value postgres "SELECT to_regclass('public.flyway_schema_history') IS NULL")" "t" \
    "истории нет в public — она в схеме game_day"
expect_contains "$(psql_value postgres "SELECT to_regclass('game_day.incident') IS NOT NULL")" "t" \
    "таблица game_day.incident создана миграцией"

out=$(app postgres); code=$?
expect_ok "$code" "второй запуск"
expect_contains "$out" 'Schema "game_day" is up to date. No migration necessary.' "второй раз Flyway ничего не применяет"
show "$(grep -m 1 'is up to date' <<<"$out")"

section "🔴 Правка применённой миграции — checksum mismatch, приложение не стартует"
# То же, что «допиши строку note в V1, пересобери и запусти»: Flyway берёт правленый файл
# из каталога вместо .jar — для него важно содержимое файла, а не откуда он взят.
dir=$(migrations_dir edited V1__game_day_incident.sql)
sed -i "/^    duty_name /a\\$NOTE_LINE" "$dir/V1__game_day_incident.sql"
expect_contains "$(cat "$dir/V1__game_day_incident.sql")" "$NOTE_LINE" "в V1 дописан столбец note"
out=$(app postgres "$dir"); code=$?
expect_failed "$code" "запуск с правленой V1"
expect_contains "$out" "Migration checksum mismatch for migration version 1" "Flyway сверил сумму и остановил старт"
expect_contains "$out" "-> Applied to database : 280339142" "сумма в истории — как в статье"
expect_contains "$out" "-> Resolved locally    : -1348780172" "сумма правленого файла — как в статье"
show "$(grep -m 1 -A 2 'Migration checksum mismatch' <<<"$out")"

section "Два файла с одним номером — Flyway не примет, приложение не стартует"
psql_value postgres "CREATE DATABASE duplicate" >/dev/null
dir=$(migrations_dir duplicate V1__game_day_incident.sql)
cp "$MIGRATION" "$dir/V1__game_day_incident_again.sql"
out=$(app duplicate "$dir"); code=$?
expect_failed "$code" "запуск с двумя V1"
expect_contains "$out" "Found more than one migration with version 1" "Flyway назвал повтор номера"
show "$(grep -m 1 -A 3 'Found more than one migration' <<<"$out")"

section "Один «_» в имени — Flyway файл не видит, таблицы нет"
psql_value postgres "CREATE DATABASE underscore" >/dev/null
dir=$(migrations_dir underscore V1_game_day_incident.sql)
out=$(app underscore "$dir"); code=$?
expect_ok "$code" "приложение стартует — ошибки нет, Flyway молчит"
expect_contains "$(psql_value underscore "SELECT to_regclass('game_day.incident') IS NULL")" "t" \
    "таблицы game_day.incident нет"
show "$(grep -i -m 3 -E 'flyway|migration' <<<"$out")"
db_down

section "flyway-core вместо стартера: Flyway молчит, падает первый запрос к таблице"
# Заодно — что статья говорит о docker ps: пока идут тесты, видны Postgres и Ryuk.
wait_tc_gone || note "контейнеры Testcontainers от прошлого прогона ещё живы"
v=$(make_variant flyway-core)
perl -0pi -e 's#<groupId>org\.springframework\.boot</groupId>(\s*)<artifactId>spring-boot-starter-flyway</artifactId>#<groupId>org.flywaydb</groupId>$1<artifactId>flyway-core</artifactId>#' "$v/pom.xml"
expect_contains "$(cat "$v/pom.xml")" "<artifactId>flyway-core</artifactId>" "в pom.xml flyway-core вместо spring-boot-starter-flyway"
(cd "$v" && timeout 900 mvn -B -ntp verify >"$v/mvn.log" 2>&1) &
pid=$!
seen=""
while kill -0 "$pid" 2>/dev/null; do
    seen+="$(tc_containers)"$'\n'
    sleep 1
done
wait "$pid"; code=$?
out=$(cat "$v/mvn.log" "$v"/target/surefire-reports/*.txt 2>/dev/null)
expect_failed "$code" "mvn verify без стартера Flyway"
expect_contains "$out" 'relation "game_day.incident" does not exist' "таблицы нет — упал запрос к ней"
show "$(grep -m 1 'does not exist' <<<"$out")"
suite=$(grep -m 1 '<testsuite' "$v/target/surefire-reports/TEST-example.gameday.GameDayApplicationTests.xml" 2>/dev/null)
if grep -q 'errors="0"' <<<"$suite" && grep -q 'failures="0"' <<<"$suite"; then
    pass "GameDayApplicationTests зелёный: приложение поднялось, Flyway не сказал ни слова"
else
    fail "GameDayApplicationTests не зелёный — статья обещает, что приложение поднимется"
fi
expect_regex "$seen" "^$IMAGE " "во время тестов docker ps показывает $IMAGE"
expect_regex "$seen" "^testcontainers/ryuk" "во время тестов docker ps показывает Ryuk"
show "$(sort -u <<<"$seen" | sed '/^$/d')"
postgres_count=$(grep -c "^$IMAGE " <<<"$(sort -u <<<"$seen")")
if [ "$postgres_count" -eq 1 ]; then
    pass "контейнер Postgres один на два тестовых класса — приложение из кэша Spring"
else
    fail "контейнеров Postgres за прогон: $postgres_count, а статья обещает один"
fi
if wait_tc_gone; then pass "после прогона контейнеры Postgres и Ryuk убраны"; else fail "после прогона остались: $(tc_images | tr '\n' ' ')"; fi

section "GameDayApplicationTests без @Import — Failed to configure a DataSource"
v=$(make_variant no-import)
sed -i -e '/^@Import(TestcontainersConfiguration.class)/d' -e '/^import org.springframework.context.annotation.Import;/d' \
    "$v/src/test/java/example/gameday/GameDayApplicationTests.java"
out=$(cd "$v" && timeout 600 mvn -B -ntp test -Dtest=GameDayApplicationTests 2>&1); code=$?
out+=$'\n'$(cat "$v"/target/surefire-reports/*.txt 2>/dev/null)
expect_failed "$code" "тест от Initializr без @Import"
expect_contains "$out" "Failed to configure a DataSource" "текст ошибки — как в статье"
show "$(grep -m 1 'Failed to configure a DataSource' <<<"$out")"

section "Docker не запущен — тесты на базе падают с Could not find a valid Docker environment"
# Docker на машине CI не остановить, не сломав соседей. Поэтому тест идёт там, где Docker нет:
# в контейнере с JDK, без сокета Docker; Maven и локальный репозиторий — с машины, без сети.
mvn_home=$(mvn -v 2>/dev/null | sed -n 's/^Maven home: //p')
repo="$HOME/.m2/repository"
if [ -z "$mvn_home" ] || [ ! -d "$repo" ]; then
    fail "не нашёл Maven ($mvn_home) или локальный репозиторий ($repo)"
else
    v=$(make_variant no-docker)
    out=$(timeout 900 docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$mvn_home":/opt/maven:ro -v "$repo":/m2 -v "$v":/work -w /work \
        eclipse-temurin:25-jdk-alpine \
        /opt/maven/bin/mvn -B -o -ntp -Dmaven.repo.local=/m2 test -Dtest=IncidentTableIT 2>&1); code=$?
    out+=$'\n'$(cat "$v"/target/surefire-reports/*.txt 2>/dev/null)
    expect_failed "$code" "mvn test без Docker"
    if grep -qF "Could not find a valid Docker environment" <<<"$out"; then
        pass "текст ошибки Testcontainers — как в статье"
        show "$(grep -m 1 'Could not find a valid Docker environment' <<<"$out")"
    else
        fail "нет «Could not find a valid Docker environment» — хвост вывода ниже"
        show "$(tail -n 30 <<<"$out")"
    fi
fi

# Убрать базу статьи, если что-то оборвалось раньше; последняя команда — с кодом 0.
db_down
