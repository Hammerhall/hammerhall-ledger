# Статья 18 «Миграции помнят решения» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 17: журнал в example.gameday.journal (18 файлов, 2 миграции), сторожа GameDayRulesTest
# (43 запуска), модель статей 12–17 в example.crm и её тесты. Java статья не добавляет; её код — пять SQL-файлов
# в open-day/ в корне песочницы: три учебные миграции схемы example, data.sql и check.sql. В mvn verify они не
# участвуют. Здесь — то, что статья обещает словами: песочница зелёная, как после статьи 17, миграций журнала
# по-прежнему две, open-day/ не видят ни Flyway, ни сторож; файлы «Пример целиком» подряд в postgres:17-alpine
# командами из статьи — что встаёт, что падает и с какой ошибкой, сколько строк осталось после чистки повторов;
# «что будет, если» — опыты 3 и 4 из статьи и V2 без умолчания; куски части 4 — те же, что в файлах; 💡 об
# умолчании-функции; ключ задач учебной CRM из части 2 — V6 из текста статьи на таблице задач (столбцы — из статей
# 12, 16 и 17): что пропускал ключ V4, что не пускает ключ без срока, пять случаев таблицы и \d; ⚠️ части 3 о
# validate — на .jar песочницы: лишнее в базе старт не роняет, пропавший столбец роняет; git log --follow; ссылки.

ARTICLE=${ROOT:-}/articles/18-migrations-remember.md
SQL=open-day
FILES='V1__open_day_invite.sql data.sql V2__open_day_invite_group.sql V3__open_day_invite_dedup_by_day.sql check.sql'
DB=open-day-db
JAR=target/game-day-0.0.1-SNAPSHOT.jar
APP_DB=game-day-db-18
APP_PASSWORD=game-day-local
PORT=${GAME_DAY_DB_PORT:-5432}
LEAD1=00000000-0000-4000-8000-000000000001

# Команды раздела «Запуск» — буква в букву, как в статье.
RUN_CMD='docker run -d --rm --name open-day-db -e POSTGRES_PASSWORD=open-day-local postgres:17-alpine'
READY_CMD='docker exec open-day-db pg_isready -h 127.0.0.1 -U postgres'
SCHEMA_CMD='docker exec open-day-db psql -U postgres -c "CREATE SCHEMA example"'
APPLY_CMD='docker exec -i open-day-db psql -U postgres -v ON_ERROR_STOP=1 -1 -f - < V1__open_day_invite.sql'
CHECK_CMD='docker exec -i open-day-db psql -U postgres -f - < check.sql'
DESCRIBE_CMD='docker exec open-day-db psql -U postgres -c "\d example.open_day_invite"'

# Отчёт Surefire о классе: «тестов N, все зелёные». Аргументы: класс, N.
suite_ok() {
    local head
    head=$(grep -m 1 '<testsuite' "target/surefire-reports/TEST-$1.xml" 2>/dev/null)
    if grep -q "tests=\"$2\"" <<<"$head" && grep -q 'failures="0"' <<<"$head" \
        && grep -q 'errors="0"' <<<"$head" && grep -q 'skipped="0"' <<<"$head"; then
        pass "$1: тестов $2, все зелёные"
    else
        fail "$1: ждали $2 зелёных — ${head:-отчёта нет}"
    fi
}

# Отчёт Surefire о классе: все тесты зелёные. Аргументы: класс, пояснение.
suite_green() {
    local head
    head=$(grep -m 1 '<testsuite' "target/surefire-reports/TEST-$1.xml" 2>/dev/null)
    if [ -n "$head" ] && grep -q 'failures="0"' <<<"$head" && grep -q 'errors="0"' <<<"$head"; then
        pass "$1 — зелёный${2:+: $2}"
    else
        fail "$1: ${head:-отчёта нет}"
    fi
}

# Сколько строк текста совпало с образцом. Аргументы: текст, образец (grep -E). Печатает число.
count_of() { LC_ALL=C.UTF-8 grep -cE -- "$2" <<<"$1"; }

# Блок кода статьи: первый блок с оградой ```<язык> после строки, которая начинается с head.
# Аргументы: начало строки, язык (пусто — блок без языка).
article_block() {
    awk -v head="$1" -v lang="$2" '
        !on && index($0, head) == 1 { on = 1; next }
        on && /^```/ {
            if (!inside) { inside = 1; want = ($0 == "```" lang); next }
            inside = 0; if (want) exit; next
        }
        on && inside && want { print }' "$ARTICLE"
}

# Файл — командой из статьи, из папки open-day: одной транзакцией, до первой ошибки. Аргумент: путь от open-day
# или полный. Вывод psql; код — как у psql.
apply() { (cd "$SQL" && docker exec -i "$DB" psql -U postgres -v ON_ERROR_STOP=1 -1 -f - <"$1" 2>&1); }

# check.sql — командой из статьи, без ON_ERROR_STOP.
run_check() { (cd "$SQL" && docker exec -i "$DB" psql -U postgres -f - <check.sql 2>&1); }

# Одно значение без рамок таблицы. Аргумент: запрос.
psql_value() { docker exec "$DB" psql -X -U postgres -tA -c "$1" 2>&1; }

# SQL со стандартного ввода; ошибка не обрывает скрипт и откатывает только свою команду.
psql_in() { docker exec -i "$DB" psql -X -U postgres -v ON_ERROR_ROLLBACK=on 2>&1; }

# Схема example заново — как свежий контейнер из опытов 3 и 4.
fresh_example() { psql_value "DROP SCHEMA IF EXISTS example CASCADE; CREATE SCHEMA example" >/dev/null; }

# Копия файла open-day с правкой perl (-0: файл целиком); путь — в VARIANT. Аргументы: имя, файл, правка, что правили.
VARIANT=""
sql_variant() {
    local dir
    dir="$VARIANTS/$(basename "$PWD")-$1"
    rm -rf "$dir" && mkdir -p "$dir"
    VARIANT="$dir/$2"
    perl -0pe "$3" "$SQL/$2" >"$VARIANT"
    if cmp -s "$VARIANT" "$SQL/$2"; then fail "вариант $1: $4 — правка не легла"; return 1; fi
    pass "в варианте: $4"
}

# Строки вывода между «== N» и следующим «== ». Аргументы: вывод, N.
segment() { awk -v n="== $2" '$0 == n { on = 1; next } /^== / { on = 0 } on' <<<"$1"; }

stop_all() {
    [ -n "${APP_PID:-}" ] && kill "$APP_PID" 2>/dev/null
    docker rm -f "$DB" "$APP_DB" >/dev/null 2>&1
    return 0
}
trap stop_all EXIT

section "Песочница после статьи 17 — по-прежнему зелёная"
suite_ok example.crm.LeadCardTest 4
suite_ok example.crm.PaidSweepTest 13
suite_ok example.crm.ReminderPointTest 8
suite_ok example.crm.CheckoutTest 11
suite_ok example.crm.RublesTest 5
suite_ok example.crm.FunnelNumbersTest 13
suite_ok example.crm.TodayListTest 3
suite_ok example.crm.ClubClientTest 21
suite_ok example.gameday.journal.GameDayRulesTest 43
note "у сторожа статьи 11 по-прежнему 43 запуска: в папку журнала ничего не попало, миграций не прибавилось"
for cls in IncidentLogTest IncidentMetricsTest IncidentTest IncidentLogIT IncidentTableIT; do
    suite_green "example.gameday.journal.$cls"
done
suite_green example.gameday.PerimeterTest "тест периметра из статьи 5"
suite_green example.gameday.GameDayApplicationTests "контекст поднялся — папка open-day ему не мешает"

section "Учебные миграции — в open-day, мимо Flyway и сторожа"
for file in $FILES; do expect_file "$SQL/$file"; done
expect_regex "$(find src/main/resources/db/migration -name '*.sql' | grep -c '')" '^2$' \
    "миграций журнала по-прежнему две"
expect_regex "$(find src/main/java/example/gameday/journal -name '*.java' | grep -c '')" '^18$' \
    "в папке журнала по-прежнему 18 файлов"
expect_regex "$(find src/main/java/example/crm -name '*.java' | grep -c ''):$(find src/test/java/example/crm -name '*.java' | grep -c '')" \
    '^17:8$' "в example.crm по-прежнему 17 классов и 8 тестов (с 16а): Java статья не добавляет"
expect_regex "$(find target -name '*open_day*' | grep -c '')" '^0$' \
    "в target нет ни одного файла open-day: сборка и Flyway папку не видят"
expect_regex "$(sed -n '/^## Пример целиком/,$p' "$ARTICLE" | grep -c '^```java')" '^0$' \
    "в «Пример целиком» нет блоков Java"
src=$(cat "$SQL"/*.sql)
expect_not_contains "$src" "game_day" "файлы open-day не трогают схему журнала"

section "Пример целиком в postgres:17-alpine — командами из статьи"
for cmd in "$RUN_CMD" "$READY_CMD" "$SCHEMA_CMD" "$APPLY_CMD" "$CHECK_CMD" "$DESCRIBE_CMD"; do
    expect_contains "$(cat "$ARTICLE")" "$cmd" "команда в статье: ${cmd:0:70}…"
done
docker rm -f "$DB" >/dev/null 2>&1
db_ok=0
if eval "$RUN_CMD" >/dev/null; then
    for ((i = 0; i < 90; i++)); do
        ready=$(eval "$READY_CMD" 2>&1) && { db_ok=1; break; }
        sleep 1
    done
fi
if [ "$db_ok" -eq 1 ]; then pass "docker run postgres:17-alpine: база принимает подключения"; else fail "база в контейнере не поднялась"; fi
if [ "$db_ok" -eq 1 ]; then
    expect_contains "$ready" "accepting connections" "pg_isready -h 127.0.0.1: ответ кончается на accepting connections"
    show "$ready"
    note "$(psql_value 'SHOW server_version')"
    expect_contains "$(eval "$SCHEMA_CMD" 2>&1)" "CREATE SCHEMA" "CREATE SCHEMA example"
    out=$(apply V1__open_day_invite.sql); code=$?
    expect_ok "$code" "V1"
    expect_contains "$out" "CREATE TABLE" "V1 — CREATE TABLE"
    out=$(apply data.sql); code=$?
    expect_ok "$code" "data.sql"
    expect_contains "$out" "INSERT 0 3" "data.sql — INSERT 0 3: ключ с sent_at пустил повтор второй ночи"
    out=$(apply V2__open_day_invite_group.sql); code=$?
    expect_ok "$code" "V2"
    expect_regex "$(count_of "$out" '^ALTER TABLE$')" '^2$' "V2 — два раза ALTER TABLE"
    expect_regex "$(psql_value "SELECT string_agg(DISTINCT group_code, ',') FROM example.open_day_invite")" '^all$' \
        "старым строкам — 'all'"
    out=$(apply V3__open_day_invite_dedup_by_day.sql); code=$?
    expect_ok "$code" "V3"
    expect_contains "$out" "DELETE 1" "V3 — DELETE 1…"
    expect_regex "$(count_of "$out" '^ALTER TABLE$')" '^2$' "…и два ALTER TABLE"
    show "$out"
    expect_regex "$(psql_value 'SELECT count(*) FROM example.open_day_invite')" '^2$' \
        "после чистки повторов в таблице две строки"
    expect_regex "$(psql_value "SELECT sent_at FROM example.open_day_invite WHERE lead_id = '$LEAD1'")" \
        '^2026-10-09 23:00:00\+00$' "у лида, которого звали дважды, осталось первое приглашение"
    out=$(run_check); code=$?
    expect_contains "$out" "(2 rows)" "check.sql: две строки…"
    expect_regex "$(count_of "$out" '\| all +\| 2026-10-17')" '^2$' "…обе с группой all"
    expect_contains "$out" 'ERROR:  duplicate key value violates unique constraint "open_day_invite_dedup"' \
        "случай 1 — повтор: duplicate key … open_day_invite_dedup"
    expect_contains "$out" \
        "DETAIL:  Key (lead_id, group_code, open_day_at)=($LEAD1, all, 2026-10-17 15:00:00+00) already exists." \
        "…в DETAIL — новый ключ: лид, группа, день"
    expect_regex "$(count_of "$out" '^INSERT 0 1$')" '^1$' "случай 2 — день другой группы: INSERT 0 1"
    expect_contains "$out" 'null value in column "group_code"' "случай 3 — без группы: null value in column \"group_code\""
    expect_contains "$out" 'violates check constraint "open_day_invite_one_channel"' \
        "случай 4 — оба канала: violates check constraint \"open_day_invite_one_channel\""
    show "$out"
    out=$(eval "$DESCRIBE_CMD" 2>&1)
    expect_contains "$out" '"open_day_invite_dedup" UNIQUE CONSTRAINT, btree (lead_id, group_code, open_day_at)' \
        "\\d: новый ключ на месте"
    show "$(sed -n '/^Indexes:/,$p' <<<"$out")"

    section "💡 Умолчание-функция — своё каждой старой строке"
    out=$(psql_in <<'EOF'
BEGIN;
ALTER TABLE example.open_day_invite ADD COLUMN new_id UUID NOT NULL DEFAULT gen_random_uuid();
SELECT count(*) || ' строк, ' || count(DISTINCT new_id) || ' разных' FROM example.open_day_invite;
ROLLBACK;
EOF
)
    expect_regex "$out" ' ([0-9]+) строк, \1 разных' "ADD COLUMN … DEFAULT gen_random_uuid(): у каждой строки свой UUID"
    show "$(grep -E 'строк, ' <<<"$out")"

    section "Старый ключ V1 и «ровно один канал» — на свежей схеме"
    fresh_example
    apply V1__open_day_invite.sql >/dev/null
    apply data.sql >/dev/null
    out=$(psql_in <<EOF
INSERT INTO example.open_day_invite (lead_id, open_day_at, email, sent_at)
VALUES ('$LEAD1', '2026-10-24T15:00:00Z', 'lead-1@example.org', '2026-10-09T23:00:00Z');
INSERT INTO example.open_day_invite (lead_id, open_day_at, sent_at)
VALUES ('00000000-0000-4000-8000-000000000003', '2026-10-24T15:00:00Z', '2026-10-11T23:00:00Z');
EOF
)
    expect_contains "$out" "Key (lead_id, sent_at)=($LEAD1, 2026-10-09 23:00:00+00) already exists." \
        "одинаковых sent_at у одного человека старый ключ не пускает: первое приглашение в группе одно"
    expect_contains "$out" 'violates check constraint "open_day_invite_one_channel"' "оба канала пусты — та же проверка"
    show "$out"

    section "Что будет, если: V3 без DELETE — опыт 3 из статьи"
    first=$(article_block "### Новый ключ — новой миграцией" sql)
    missing=$(grep -v '^$' <<<"$first" | grep -vxF -f "$SQL/V3__open_day_invite_dedup_by_day.sql")
    if [ -n "$first" ] && [ -z "$missing" ]; then pass "кусок части 4 «первое, что хочется написать» — строки V3"; else
        fail "кусок части 4 расходится с V3"; show "$missing"; fi
    fresh_example
    for file in V1__open_day_invite.sql data.sql V2__open_day_invite_group.sql; do apply "$file" >/dev/null; done
    if sql_variant no-delete V3__open_day_invite_dedup_by_day.sql 's/\nDELETE FROM .*?;\n//s' "из V3 удалён весь DELETE … ;"; then
        out=$(apply "$VARIANT"); code=$?
        expect_failed "$code" "V3 без DELETE"
        expect_contains "$out" 'ERROR:  could not create unique index "open_day_invite_dedup"' "ошибка — как в части 4"
        expect_contains "$out" \
            "DETAIL:  Key (lead_id, group_code, open_day_at)=($LEAD1, all, 2026-10-17 15:00:00+00) is duplicated." \
            "в DETAIL — повтор: лид, группа all, день 17 октября"
        show "$out"
        out=$(eval "$DESCRIBE_CMD" 2>&1)
        expect_contains "$out" '"open_day_invite_dedup" UNIQUE CONSTRAINT, btree (lead_id, sent_at)' \
            "\\d: старый ключ на месте — транзакция откатилась вместе с DROP CONSTRAINT"
        expect_regex "$(psql_value 'SELECT count(*) FROM example.open_day_invite')" '^3$' "в таблице по-прежнему три строки"
        show "$(sed -n '/^Indexes:/,$p' <<<"$out")"
    fi

    section "Что будет, если: V2 без DROP DEFAULT — опыт 4 из статьи"
    fresh_example
    if sql_variant keep-default V2__open_day_invite_group.sql \
        's/\n+ALTER TABLE example\.open_day_invite\n +ALTER COLUMN group_code DROP DEFAULT;//' \
        "из V2 удалён второй ALTER TABLE — с DROP DEFAULT"; then
        apply V1__open_day_invite.sql >/dev/null
        apply data.sql >/dev/null
        apply "$VARIANT" >/dev/null
        apply V3__open_day_invite_dedup_by_day.sql >/dev/null
        out=$(run_check)
        expect_regex "$(count_of "$out" '^INSERT 0 1$')" '^2$' "случай 3 прошёл: INSERT 0 1 — у двух случаев из четырёх"
        expect_not_contains "$out" 'null value in column' "ошибки NOT NULL нет"
        expect_regex "$(psql_value "SELECT group_code FROM example.open_day_invite WHERE open_day_at = '2026-10-24T15:00:00Z'")" \
            '^all$' "приглашение без группы тихо ушло на «общий» день all"
    fi

    section "Что будет, если: V2 без умолчания — NOT NULL на таблице со строками"
    fresh_example
    if sql_variant no-default V2__open_day_invite_group.sql "s/ DEFAULT 'all'//" "ADD COLUMN … NOT NULL без DEFAULT 'all'"; then
        apply V1__open_day_invite.sql >/dev/null
        apply data.sql >/dev/null
        out=$(apply "$VARIANT"); code=$?
        expect_failed "$code" "V2 без умолчания"
        expect_contains "$out" 'column "group_code" of relation "open_day_invite" contains null values' \
            "contains null values — как в статье 9"
        show "$out"
    fi

    section "Часть 2: ключ задач учебной CRM — V6 из текста статьи"
    key_v4='    CONSTRAINT task_dedup UNIQUE (kind, person_id, due_at)'
    index_v4='CREATE INDEX ix_task_open_due ON sales.task (due_at) WHERE done_at IS NULL;'
    expect_contains "$(cat "$ARTICLE")" "$key_v4" "в статье — ключ V4"
    expect_contains "$(cat "$ARTICLE")" "$index_v4" "в статье — частичный индекс V4"
    v6=$(awk '/^-- учебная CRM клуба: V6__/ { on = 1 } on && /^```$/ { exit } on' "$ARTICLE")
    expect_contains "$v6" "ADD CONSTRAINT task_dedup UNIQUE (kind, person_id, group_id, until_at);" "V6 взят из статьи"
    # Таблица задач: столбцы — из статей 12, 16 и 17; ключ и индекс — строки V4 из статьи.
    out=$(psql_in <<EOF
CREATE SCHEMA sales;
CREATE TABLE sales.task (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    kind        VARCHAR(20)   NOT NULL,
    person_id   UUID          NOT NULL,
    group_id    UUID,
    due_at      TIMESTAMPTZ   NOT NULL,
    until_at    TIMESTAMPTZ,
    note        TEXT          NOT NULL,
    created_at  TIMESTAMPTZ   NOT NULL,
    done_at     TIMESTAMPTZ,
$key_v4
);
$index_v4
EOF
)
    expect_contains "$out" "CREATE INDEX" "таблица задач с ключом V4"
    hold="INSERT INTO sales.task (kind, person_id, group_id, due_at, until_at, note, created_at, done_at) VALUES"
    person=00000000-0000-4000-8000-000000000001
    group=00000000-0000-4000-8000-000000000100
    out=$(psql_in <<EOF
BEGIN;
$hold ('HOLD', '$person', '$group', '2026-10-05T08:15:00Z', '2026-10-06T08:00:00Z', 'x', '2026-10-05T08:15:00Z', NULL);
$hold ('HOLD', '$person', '$group', '2026-10-05T08:45:00Z', '2026-10-06T08:00:00Z', 'x', '2026-10-05T08:45:00Z', NULL);
SELECT kind, due_at, until_at FROM sales.task ORDER BY due_at;
ROLLBACK;
EOF
)
    expect_regex "$(count_of "$out" '^INSERT 0 1$')" '^2$' "ключ V4: опрос в 11:45 завёл вторую задачу о той же брони"
    expected=$(article_block "Теперь вспомни, какой срок у задачи по брони" "")
    got=$(sed 's/[[:space:]]*$//' <<<"$out" | grep -xF -f <(grep -v '^$' <<<"$expected"))
    if [ -n "$expected" ] && [ "$got" = "$expected" ]; then pass "таблица после двух опросов — как в статье"; else
        fail "таблица после двух опросов расходится со статьёй"; show "$out"; fi
    show "$out"
    out=$(psql_in <<EOF
BEGIN;
ALTER TABLE sales.task DROP CONSTRAINT task_dedup;
ALTER TABLE sales.task ADD CONSTRAINT task_dedup UNIQUE (kind, person_id, group_id);
$hold ('HOLD', '$person', '$group', '2026-10-05T08:15:00Z', '2026-10-06T08:00:00Z', 'x', '2026-10-05T08:15:00Z',
       '2026-10-06T08:15:00Z');
$hold ('HOLD', '$person', '$group', '2026-10-07T07:15:00Z', '2026-10-08T07:00:00Z', 'x', '2026-10-07T07:15:00Z', NULL);
ROLLBACK;
EOF
)
    expect_contains "$out" 'ERROR:  duplicate key value violates unique constraint "task_dedup"' \
        "ключ без срока: новая бронь того же места — duplicate key…"
    expect_contains "$out" "Key (kind, person_id, group_id)=(HOLD, $person, $group) already exists." \
        "…в DETAIL — HOLD, человек, группа: закрытая задача держит ключ"
    show "$(grep -E '^(ERROR|DETAIL)' <<<"$out")"
    out=$(docker exec -i "$DB" psql -U postgres -v ON_ERROR_STOP=1 -1 -f - <<<"$v6" 2>&1); code=$?
    expect_ok "$code" "V6 из статьи — на таблице без задач по брони"
    expect_regex "$(count_of "$out" '^ALTER TABLE$')" '^2$' "V6 — DROP CONSTRAINT и ADD CONSTRAINT"
    psql_value "ALTER TABLE sales.task ADD COLUMN hold_id UUID" >/dev/null
    out=$(docker exec "$DB" psql -U postgres -c '\d sales.task' 2>&1)
    expected=$(article_block "Итог всех файлов показывает" "")
    got=$(sed -n '/^Indexes:/,/^$/p' <<<"$out" | grep -v '^$')
    if [ -n "$expected" ] && [ "$got" = "$expected" ]; then pass "\\d sales.task после V7: раздел индексов — как в статье"; else
        fail "\\d sales.task расходится со статьёй"; show "$got"; fi
    show "$got"
    out=$(psql_in <<EOF
BEGIN;
\echo == 0
$hold ('HOLD', '$person', '$group', '2026-10-05T08:15:00Z', '2026-10-06T08:00:00Z', 'x', '2026-10-05T08:15:00Z', NULL);
\echo == 1
$hold ('HOLD', '$person', '$group', '2026-10-05T08:45:00Z', '2026-10-06T08:00:00Z', 'x', '2026-10-05T08:45:00Z', NULL);
\echo == 2
$hold ('HOLD', '$person', '00000000-0000-4000-8000-000000000200', '2026-10-05T08:15:00Z', '2026-10-06T08:00:00Z', 'x',
       '2026-10-05T08:15:00Z', NULL);
\echo == 3
UPDATE sales.task SET done_at = '2026-10-06T08:15:00Z' WHERE kind = 'HOLD' AND group_id = '$group';
$hold ('HOLD_EXPIRED', '$person', '$group', '2026-10-06T08:15:00Z', '2026-10-06T08:00:00Z', 'x', '2026-10-06T08:15:00Z', NULL);
\echo == 4
$hold ('HOLD', '$person', '$group', '2026-10-06T08:45:00Z', '2026-10-06T08:00:00Z', 'x', '2026-10-06T08:45:00Z', NULL);
\echo == 5
$hold ('HOLD', '$person', '$group', '2026-10-07T07:15:00Z', '2026-10-08T07:00:00Z', 'x', '2026-10-07T07:15:00Z', NULL);
\echo == end
ROLLBACK;
EOF
)
    expect_contains "$(segment "$out" 0)" "INSERT 0 1" "опрос 11:15 — задача заведена"
    expect_contains "$(segment "$out" 1)" 'ERROR:  duplicate key value violates unique constraint "task_dedup"' \
        "опрос 11:45 — повтор не пускает…"
    expect_contains "$(segment "$out" 1)" \
        "Key (kind, person_id, group_id, until_at)=(HOLD, $person, $group, 2026-10-06 08:00:00+00) already exists." \
        "…в DETAIL четыре столбца и срок брони 2026-10-06 08:00:00+00"
    expect_contains "$(segment "$out" 2)" "INSERT 0 1" "бронь того же человека в другой группе — заводит"
    expect_contains "$(segment "$out" 3)" "INSERT 0 1" "«место ушло» по той же брони — заводит: вид другой"
    expect_contains "$(segment "$out" 4)" 'duplicate key value violates unique constraint "task_dedup"' \
        "задачу закрыли, опрос снова видит бронь — не пускает"
    expect_contains "$(segment "$out" 5)" "INSERT 0 1" "забронировал место снова — заводит: срок брони другой"
    show "$out"
    start=$(date -ud '2026-10-05T08:15:00Z' +%s)
    held_until=$(date -ud '2026-10-06T08:00:00Z' +%s)
    polls=0
    last=$start
    for ((t = start; t < held_until; t += 1800)); do polls=$((polls + 1)); last=$t; done
    moscow() { LC_ALL=C TZ=Europe/Moscow date -d "@$1" '+%a %H:%M'; }
    expect_regex "$polls $(moscow "$start") $(moscow "$last")" '^48 Mon 11:15 Tue 10:45$' \
        "бронь до 06.10 11:00 опрос в :15 и :45 видит 48 раз, с 11:15 понедельника до 10:45 вторника"
    docker rm -f "$DB" >/dev/null 2>&1
fi

section "Часть 3: validate на .jar песочницы — лишнее в базе старт не роняет"
expect_file "$JAR"
# Каталог миграций для запуска: копии миграций журнала и третья — проба. Аргументы: имя, SQL пробы. Печатает путь.
probe_migrations() {
    local dir
    dir="$VARIANTS/$(basename "$PWD")-$1"
    rm -rf "$dir" && mkdir -p "$dir"
    cp src/main/resources/db/migration/*.sql "$dir/"
    printf '%s\n' "$2" >"$dir/V3__validate_probe.sql"
    echo "$dir"
}
# Песочница на базе $APP_DB с миграциями из каталога: ждём «атакующих …», падения или выхода. Печатает лог.
app_run() {
    local log i code=1
    log=$(mktemp)
    env SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:$PORT/postgres" SPRING_DATASOURCE_USERNAME=postgres \
        SPRING_DATASOURCE_PASSWORD="$APP_PASSWORD" SPRING_FLYWAY_LOCATIONS="filesystem:$1" \
        java "${UTF8[@]}" -jar "$JAR" --server.port=0 >"$log" 2>&1 &
    APP_PID=$!
    for ((i = 0; i < 180; i++)); do
        if grep -qE 'атакующих [0-9]' "$log"; then code=0; break; fi
        kill -0 "$APP_PID" 2>/dev/null || break
        sleep 1
    done
    kill "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null
    APP_PID=""
    cat "$log"
    rm -f "$log"
    return "$code"
}
app_ok=0
docker rm -f "$APP_DB" >/dev/null 2>&1
if [ -f "$JAR" ] && docker run -d --rm --name "$APP_DB" -p "127.0.0.1:$PORT:5432" \
    -e POSTGRES_PASSWORD="$APP_PASSWORD" postgres:17-alpine >/dev/null; then
    for ((i = 0; i < 90; i++)); do
        if docker exec "$APP_DB" pg_isready -q -h 127.0.0.1 -U postgres; then app_ok=1; break; fi
        sleep 1
    done
fi
if [ "$app_ok" -eq 1 ]; then pass "база для песочницы поднялась на 127.0.0.1:$PORT"; else fail "база для песочницы не поднялась"; fi
if [ "$app_ok" -eq 1 ]; then
    dir=$(probe_migrations extra "-- Лишнее в базе: столбец, CHECK, UNIQUE, индекс; снят NOT NULL, другая длина, умолчание.
ALTER TABLE game_day.incident ADD COLUMN extra TEXT;
ALTER TABLE game_day.incident ADD CONSTRAINT incident_probe_check CHECK (duty_name <> 'nobody');
ALTER TABLE game_day.incident ADD CONSTRAINT incident_probe_unique UNIQUE (title, detected_at);
CREATE INDEX ix_incident_probe ON game_day.incident (duty_name);
ALTER TABLE game_day.incident ALTER COLUMN duty_name DROP NOT NULL;
ALTER TABLE game_day.incident ALTER COLUMN duty_name SET DEFAULT 'duty-0';
ALTER TABLE game_day.incident ALTER COLUMN title TYPE VARCHAR(100);")
    out=$(app_run "$dir"); code=$?
    expect_ok "$code" "песочница с лишним в базе"
    expect_contains "$out" 'Successfully applied 3 migrations to schema "game_day", now at version v3' "Flyway применил пробу"
    expect_not_contains "$out" "Schema validation" "validate промолчал: лишнего не ищет, NOT NULL, длину и умолчание не сравнивает"
    show "$(grep -E 'Successfully applied|атакующих' <<<"$out")"
    docker exec "$APP_DB" psql -X -U postgres -q -c "DROP SCHEMA game_day CASCADE" >/dev/null 2>&1
    dir=$(probe_migrations missing "ALTER TABLE game_day.incident DROP COLUMN fixed_at;")
    out=$(app_run "$dir"); code=$?
    expect_failed "$code" "контроль: песочница без столбца fixed_at"
    expect_contains "$out" "Schema validation: missing column [fixed_at] in table [game_day.incident]" \
        "validate включён: пропавший столбец роняет старт — та же ошибка, что в статье 3б"
    show "$(grep -m 1 -o 'Schema validation: missing column [^]]*] in table [^]]*]' <<<"$out")"
fi
docker rm -f "$APP_DB" >/dev/null 2>&1

section "git log --follow — история сквозь переименование"
repo="$VARIANTS/$(basename "$PWD")-git"
rm -rf "$repo" && mkdir -p "$repo/db"
g() { git -C "$repo" -c user.name=example -c user.email=example@example.org "$@"; }
g init -q
echo "ALTER TABLE t ADD COLUMN c INT;" >"$repo/db/V7__t_c.sql"
g add . && GIT_AUTHOR_DATE=2026-10-08T10:00:00Z GIT_COMMITTER_DATE=2026-10-08T10:00:00Z g commit -qm "Столбец c"
g mv db/V7__t_c.sql db/V8__t_c.sql
GIT_AUTHOR_DATE=2026-10-09T10:00:00Z GIT_COMMITTER_DATE=2026-10-09T10:00:00Z g commit -qm "Номер V7 занят — V8"
with=$(g log --follow --format='%h %ad %s' --date=short -- db/V8__t_c.sql)
without=$(g log --format='%h %ad %s' --date=short -- db/V8__t_c.sql)
expect_regex "$(grep -c '' <<<"$with")" '^2$' "с --follow — два коммита: переименование и появление файла"
expect_regex "$(grep -c '' <<<"$without")" '^1$' "без --follow — один: коммит, где файл появился, выпал"
expect_regex "$(tail -n 1 <<<"$with")" '^[0-9a-f]{7,} 2026-10-08 Столбец c$' "строка — номер, дата без времени, заголовок"
show "$with"

section "Первоисточники открываются"
for link in https://documentation.red-gate.com/fd/versioned-migrations-273973333.html \
    https://documentation.red-gate.com/fd/migration-transaction-handling-273973399.html \
    https://www.postgresql.org/docs/17/sql-altertable.html \
    https://www.postgresql.org/docs/17/sql-delete.html \
    https://docs.hibernate.org/orm/7.4/introduction/html_single/ \
    https://git-scm.com/docs/git-log; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
