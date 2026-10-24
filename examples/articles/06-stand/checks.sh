# Статья 6 «Стенд своими руками» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 5: Postgres, веб, охрана; без базы приложение не стартует. Тесты песочницы
# из статей 2–5 уже прошли в mvn verify — с Actuator и правилом health в SecurityConfig. Здесь — то, что
# статья обещает словами: до правила health — 401, после — UP без входа, остальной Actuator закрыт; образ
# на alpine не от root; docker run с адресом базы 127.0.0.1 падает; стенд compose с базой (db здорова, порт
# базы закрыт, приложение ходит в неё по db:5432, охрана та же); сеть изнутри; база остановлена — 503;
# том переживает down и пропадает после down -v; пароль живёт в томе; ENTRYPOINT списком и строкой;
# без стоп-слова — APPLICATION FAILED TO START; без правила health — unhealthy; без volumes: — ошибка.

HEALTH_JSON='{"groups":["liveness","readiness"],"status":"UP"}'
JAR=target/game-day-0.0.1-SNAPSHOT.jar
SECURITY=src/main/java/example/gameday/SecurityConfig.java
HEALTH_RULE='.requestMatchers(HttpMethod.GET, "/actuator/health").permitAll()'
ADMIN=admin:admin-local
LOCAL=http://127.0.0.1:8080
STAND=http://127.0.0.1:8088
HOST_DB=game-day-db
HOST_DB_PASSWORD=game-day-local
HOST_DB_PORT=${GAME_DAY_DB_PORT:-5432}
DB_PASSWORD=$(grep -m 1 '^GAME_DAY_DB_PASSWORD=' .env.example | cut -d= -f2-)
DB_CONTAINER=game-day-db-1
APP_CONTAINER=game-day-game-day-1
NETWORK=game-day_default
VOLUME=game-day_db-data
COUNT_SQL='SELECT count(*) FROM game_day.incident'
APP_PID=""
NOHEALTH=""

# База статьи 3а — docker run на 127.0.0.1; ждём, пока Postgres примет подключение по TCP.
host_db_up() {
    docker rm -f "$HOST_DB" >/dev/null 2>&1
    docker run -d --rm --name "$HOST_DB" -p "127.0.0.1:$HOST_DB_PORT:5432" \
        -e POSTGRES_PASSWORD="$HOST_DB_PASSWORD" postgres:17-alpine >/dev/null || return 1
    local i
    for ((i = 0; i < 90; i++)); do
        docker exec "$HOST_DB" pg_isready -q -h 127.0.0.1 -U postgres && return 0
        sleep 1
    done
    return 1
}

host_db_down() { docker rm -f "$HOST_DB" >/dev/null 2>&1; return 0; }

# Приложение, как в статье 5: java -jar, адрес базы — переменными окружения; работает в фоне, лог — в файл.
# Готово, когда main напечатал настройки игры: к этому времени Tomcat уже слушает порт. Код 1 — не дождались.
app_start() {
    local jar=$1 log=$2 i
    env SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:$HOST_DB_PORT/postgres" \
        SPRING_DATASOURCE_USERNAME=postgres SPRING_DATASOURCE_PASSWORD="$HOST_DB_PASSWORD" \
        java "${UTF8[@]}" -jar "$jar" >"$log" 2>&1 &
    APP_PID=$!
    for ((i = 0; i < 180; i++)); do
        grep -qF "атакующих 2" "$log" && return 0
        kill -0 "$APP_PID" 2>/dev/null || return 1
        sleep 1
    done
    return 1
}

app_stop() {
    [ -n "$APP_PID" ] || return 0
    kill "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null
    APP_PID=""
    return 0
}

# curl -i, как в статье; \r из заголовков убираем, чтобы сверять построчно.
http() { curl -sS -i "$@" 2>&1 | tr -d '\r'; }
status_of() { head -n 1 <<<"$1"; }
body_of() { sed '1,/^$/d' <<<"$1"; }

# Сколько происшествий в базе стенда: psql внутри контейнера службы db, одно число.
incidents() { docker compose exec -T db psql -X -U postgres -tA -c "$COUNT_SQL" 2>&1; }

# То же — как в статье, таблицей psql.
incidents_table() { docker compose exec -T db psql -X -U postgres -c "$COUNT_SQL" 2>&1; }

# Ждать строку в логе службы; печатает лог. Код 1 — не дождались.
wait_log() {
    local service=$1 text=$2 seconds=$3 logs="" i
    for ((i = 0; i < seconds; i++)); do
        logs=$(docker compose logs "$service" 2>&1)
        if grep -qF -- "$text" <<<"$logs"; then
            echo "$logs"
            return 0
        fi
        sleep 1
    done
    echo "$logs"
    return 1
}

# Ждать, пока адрес ответит 2xx, — по часам: один запрос без базы идёт десятки секунд. Печатает, сколько ждали.
wait_up() {
    local url=$1 seconds=$2 start
    start=$(date +%s)
    while (($(date +%s) - start < seconds)); do
        if curl -fsS -m 40 -o /dev/null "$url" 2>/dev/null; then
            echo "$(($(date +%s) - start))"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Отчёт Surefire о классе: все тесты зелёные.
suite_green() {
    local head
    head=$(grep -m 1 '<testsuite' "target/surefire-reports/TEST-$1.xml" 2>/dev/null)
    if [ -n "$head" ] && grep -q 'failures="0"' <<<"$head" && grep -q 'errors="0"' <<<"$head"; then
        pass "$1 — зелёный: $2"
    else
        fail "$1: ${head:-отчёта нет}"
    fi
}

cleanup() {
    app_stop
    docker rm -f game-day-try game-day-shell >/dev/null 2>&1
    host_db_down
    docker compose down -v >/dev/null 2>&1
    if [ -n "$NOHEALTH" ]; then (cd "$NOHEALTH" && docker compose down -v >/dev/null 2>&1); fi
    return 0
}
cleanup
trap cleanup EXIT

section "Actuator в pom.xml, правило health в SecurityConfig; тесты песочницы зелёные"
expect_contains "$(cat pom.xml)" "<artifactId>spring-boot-starter-actuator</artifactId>" \
    "в pom.xml — spring-boot-starter-actuator"
expect_contains "$(cat "$SECURITY")" "$HEALTH_RULE" "в SecurityConfig — GET /actuator/health для всех"
suite_green example.gameday.PerimeterTest "health тест периметра не видит, строка в DECLARED не нужна"
suite_green example.gameday.GameDayApplicationTests "приложение с Actuator поднимается"
suite_green example.gameday.journal.IncidentListControllerTest "охрана журнала прежняя"
suite_green example.gameday.journal.IncidentControllerTest "охрана ручки по номеру прежняя"

section "Как в статье 5, без правила: health — 401, его закрыл denyAll"
if host_db_up; then
    pass "база статьи 3а: docker run postgres:17-alpine на 127.0.0.1:$HOST_DB_PORT"
else
    fail "база в docker run не поднялась"
fi
v=$(make_variant no-health-rule)
grep -vF -- "$HEALTH_RULE" "$SECURITY" >"$v/$SECURITY"
if cmp -s "$SECURITY" "$v/$SECURITY"; then fail "из SecurityConfig варианта правило не убралось"; fi
if (cd "$v" && mvn -B -q -ntp -DskipTests package >/dev/null 2>&1); then
    if app_start "$v/$JAR" target/app-no-rule.log; then
        out=$(http "$LOCAL/actuator/health")
        expect_regex "$(status_of "$out")" '^HTTP/1\.1 401 ?$' "curl -i /actuator/health без правила — 401"
        expect_regex "$out" '^WWW-Authenticate: Basic realm="Realm", charset="UTF-8"$' "…с просьбой войти по Basic"
        body=$(body_of "$out")
        expect_contains "$body" '"status":401' "тело — форма Boot: status 401"
        expect_contains "$body" '"error":"Unauthorized"' "…error Unauthorized"
        expect_contains "$body" '"path":"/actuator/health"' "…path /actuator/health"
        show "$out"
    else
        fail "вариант без правила не поднялся"
        show "$(tail -n 30 target/app-no-rule.log)"
    fi
    app_stop
else
    fail "вариант без правила не собрался"
fi

section "С правилом: health без входа — UP; пробы, /actuator и журнал — только со входом"
if app_start "$JAR" target/app.log; then
    out=$(curl -fsS "$LOCAL/actuator/health" 2>&1); code=$?
    expect_ok "$code" "curl -fsS /actuator/health без входа"
    expect_contains "$out" "$HEALTH_JSON" "ответ — как в статье, без подробностей о базе"
    show "$out"
    for path in /actuator/health/liveness /actuator/health/readiness /actuator /game-day/incidents; do
        expect_regex "$(status_of "$(http "$LOCAL$path")")" '^HTTP/1\.1 401 ?$' "$path без входа — 401"
    done
    expect_regex "$(status_of "$(http -u "$ADMIN" "$LOCAL/actuator")")" '^HTTP/1\.1 403 ?$' \
        "/actuator под admin — 403: правила для него нет, сработал denyAll"
else
    fail "приложение не поднялось"
    show "$(tail -n 30 target/app.log)"
fi
app_stop

section "Обёртка Maven — как кладёт Initializr"
if mvn -B -q -ntp -N wrapper:wrapper -Dtype=only-script >/dev/null 2>&1 && [ -x mvnw ] && [ -d .mvn ]; then
    pass "mvnw и .mvn/ на месте"
else
    fail "не удалось завести mvnw"
fi

section "Образ: две ступени, не от root"
out=$(docker build -t game-day:local . 2>&1); code=$?
expect_ok "$code" "docker build на eclipse-temurin:25-*-alpine"
[ "$code" -eq 0 ] || show "$(tail -n 40 <<<"$out")"
expect_contains "$(docker image inspect -f '{{.Config.User}}' game-day:local 2>&1)" "gameday" "USER gameday"

section "Контейнер руками: адрес базы 127.0.0.1 — это сам контейнер"
docker rm -f game-day-try >/dev/null 2>&1
docker run -d --name game-day-try -p 127.0.0.1:8088:8080 \
    -e SPRING_DATASOURCE_URL=jdbc:postgresql://127.0.0.1:5432/postgres \
    -e SPRING_DATASOURCE_USERNAME=postgres -e SPRING_DATASOURCE_PASSWORD=game-day-local \
    game-day:local >/dev/null
expect_ok $? "docker run -d --name game-day-try … game-day:local — как в статье"
for _ in $(seq 120); do
    [ "$(docker inspect -f '{{.State.Running}}' game-day-try 2>/dev/null)" = true ] || break
    sleep 1
done
expect_not_contains "$(docker ps --format '{{.Names}}' 2>&1)" "game-day-try" "docker ps: game-day-try в списке нет"
status=$(docker ps -a --filter name=game-day-try --format '{{.Status}}' 2>&1)
expect_contains "$status" "Exited (1)" "docker ps -a: Exited (1)"
show "$status"
logs=$(docker logs game-day-try 2>&1)
expect_contains "$logs" "Connection to 127.0.0.1:5432 refused" "в логе — Connection to 127.0.0.1:5432 refused"
show "$(grep -m 1 -o 'Connection to 127\.0\.0\.1:5432 refused[^"]*' <<<"$logs")"
if [ "$HOST_DB_PORT" = 5432 ] && docker exec "$HOST_DB" pg_isready -q -h 127.0.0.1 -U postgres; then
    pass "а база статьи 3а в это время принимает подключения на 127.0.0.1:5432 машины"
else
    note "база на машине — на 127.0.0.1:$HOST_DB_PORT, не на 5432: сравнение с java -jar неполное"
fi
docker rm game-day-try >/dev/null 2>&1
expect_ok $? "docker rm game-day-try"
host_db_down

section "compose: файл принимается; без раздела volumes — нет"
cp .env.example .env
expect_contains "$(cat .env.example)" "GAME_DAY_DB_PASSWORD=change-me" "в .env.example пароль базы — явно фальшивый"
[ -n "$DB_PASSWORD" ] || fail "в .env.example нет GAME_DAY_DB_PASSWORD"
out=$(docker compose config 2>&1); code=$?
expect_ok "$code" "docker compose config"
expect_not_contains "$out" "variable is not set" "все переменные из .env подставлены"
expect_contains "$out" "name: $NETWORK" "сеть проекта — $NETWORK"
expect_contains "$out" "name: $VOLUME" "том проекта — $VOLUME"
db_ports=$(docker compose config --format json 2>/dev/null | python3 -I -c '
import json, sys
print("портов нет" if not json.load(sys.stdin)["services"]["db"].get("ports") else "порты есть")' 2>&1)
expect_contains "$db_ports" "портов нет" "у службы db в compose.yaml портов нет"
v=$(make_variant no-volumes)
sed -i '/^volumes:$/,$d' "$v/compose.yaml"
out=$(cd "$v" && docker compose config 2>&1); code=$?
expect_failed "$code" "docker compose config без раздела volumes: в конце файла"
expect_contains "$out" 'service "db" refers to undefined volume db-data' "…service \"db\" refers to undefined volume db-data"
show "$(grep 'undefined volume' <<<"$out")"

section "compose и скрипты: поднять стенд с базой"
chmod +x stand/*.sh
bash -n stand/game-up.sh
expect_ok $? "bash -n stand/game-up.sh"
bash -n stand/game-alive.sh
expect_ok $? "bash -n stand/game-alive.sh"
out=$(stand/game-up.sh 2>&1); code=$?
expect_ok "$code" "stand/game-up.sh"
expect_contains "$out" "$HEALTH_JSON" "health снаружи — как в статье"
expect_contains "$out" "игра жива" "скрипт сказал «игра жива»"
show "$(tail -n 3 <<<"$out")"
ps=$(docker compose ps 2>&1)
expect_regex "$ps" "^$DB_CONTAINER .*\(healthy\)" "docker compose ps: db — (healthy)"
expect_regex "$ps" "^$APP_CONTAINER .*\(healthy\)" "docker compose ps: game-day — (healthy)"
show "$ps"
logs=$(docker compose logs game-day 2>&1)
expect_contains "$logs" "атакующих 4" "в логе «атакующих 4» — профиль stand"
expect_contains "$logs" 'Successfully applied 1 migration to schema "game_day"' "Flyway применил миграцию: база новая"
show "$(grep -m 1 -o 'игра PT3H, атакующих 4' <<<"$logs")"

section "База: db здорова, порт наружу не опубликован, приложение ходит в неё по db:5432"
health=$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>&1)
if [ "$health" = healthy ]; then pass "pg_isready: $DB_CONTAINER — healthy"; else fail "$DB_CONTAINER: $health"; fi
ports=$(docker port "$DB_CONTAINER" 2>&1)
if [ -z "$ports" ]; then pass "docker port $DB_CONTAINER пуст — порт базы наружу закрыт"; else fail "у базы опубликован порт: $ports"; fi
app_env=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$APP_CONTAINER" 2>&1)
expect_contains "$app_env" "SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/postgres" \
    "у приложения адрес базы — db:5432, имя службы"
expect_not_contains "$app_env" "GAME_DAY_DB_PASSWORD" "самого .env в контейнере нет — только строки из environment"
app_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$APP_CONTAINER" 2>&1)
clients=$(docker compose exec -T db psql -X -U postgres -tA \
    -c "SELECT DISTINCT host(client_addr) FROM pg_stat_activity WHERE client_addr IS NOT NULL" 2>&1)
if [ -n "$app_ip" ] && grep -qxF -- "$app_ip" <<<"$clients"; then
    pass "подключения к базе — по сети compose, из контейнера приложения ($app_ip)"
else
    fail "среди подключений к базе нет контейнера приложения: «$clients», приложение — «$app_ip»"
fi
count=$(incidents)
if [ "$count" = 1 ]; then pass "в журнале одно происшествие — его записал запуск"; else fail "в журнале «$count», ждали 1"; fi

section "Охрана на стенде та же: журнал без входа — 401, под admin — 200; пробы закрыты"
out=$(http "$STAND/game-day/incidents")
expect_regex "$(status_of "$out")" '^HTTP/1\.1 401 ?$' "curl -i /game-day/incidents без входа — 401"
out=$(curl -sS -u "$ADMIN" "$STAND/game-day/incidents" 2>&1)
expect_contains "$out" '"title":"Брокер не отвечает"' "под admin — «Брокер не отвечает»"
expect_contains "$out" '"total":1' "…и \"total\":1"
show "$out"
expect_regex "$(status_of "$(http "$STAND/actuator/health/liveness")")" '^HTTP/1\.1 401 ?$' \
    "/actuator/health/liveness без входа — 401"

section "Сеть изнутри: имя службы, а не 127.0.0.1:8088"
out=$(docker compose exec -T game-day wget -qO- http://game-day:8080/actuator/health 2>&1); code=$?
expect_ok "$code" "exec -T: wget по game-day:8080"
expect_contains "$out" '"status":"UP"' "status UP по имени службы"
out=$(docker compose exec -T game-day wget -qO- http://127.0.0.1:8088/actuator/health 2>&1); code=$?
expect_failed "$code" "127.0.0.1:8088 изнутри контейнера"
show "$out"

section "База остановлена: health — DOWN и 503, game-alive.sh — код 1; база вернулась — снова UP"
docker compose stop db >/dev/null 2>&1
expect_ok $? "docker compose stop db"
if [ "$(docker inspect -f '{{.State.Running}}' "$APP_CONTAINER" 2>&1)" = true ]; then
    pass "приложение работает дальше — stop db его не остановил"
else
    fail "после stop db контейнер приложения не работает"
fi
out=$(curl -sS -i -m 120 "$STAND/actuator/health" 2>&1 | tr -d '\r')
expect_regex "$(status_of "$out")" '^HTTP/1\.1 503 ?$' "health без базы — 503"
expect_contains "$(body_of "$out")" '"status":"DOWN"' "…и \"status\":\"DOWN\""
show "$(status_of "$out")"$'\n'"$(body_of "$out")"
start=$(date +%s)
out=$(stand/game-alive.sh 2>&1); code=$?
took=$(($(date +%s) - start))
if [ "$code" -eq 1 ]; then pass "game-alive.sh: код 1"; else fail "game-alive.sh: код $code, ждали 1"; fi
expect_contains "$out" "curl: (22) The requested URL returned error: 503" "curl: (22) … 503 — как в статье"
expect_contains "$out" "игра не отвечает на $STAND/actuator/health" "…и подсказка скрипта"
if [ "$took" -ge 5 ]; then
    pass "ответ пришёл не сразу — через $took с: приложение ждало подключения к базе"
else
    fail "ответ пришёл за $took с, а статья говорит «не сразу»"
fi
show "$out"
docker compose start db >/dev/null 2>&1
expect_ok $? "docker compose start db"
if took=$(wait_up "$STAND/actuator/health" 180); then
    pass "health снова UP через $took с после start db"
else
    fail "после start db health не вернулся в UP за 180 с"
fi
out=$(stand/game-alive.sh 2>&1); code=$?
expect_ok "$code" "game-alive.sh после start db"
expect_contains "$out" "игра жива" "…«игра жива»"
started=$(grep -c "Started GameDayApplication" <<<"$(docker compose logs game-day 2>&1)")
if [ "$started" = 1 ]; then
    pass "приложение не перезапускалось — переподключилось к базе само"
else
    fail "«Started GameDayApplication» в логе $started раз, ждали 1"
fi

section "ENTRYPOINT списком: docker compose stop — Java закрывается за секунды"
start=$(date +%s)
docker compose stop game-day >/dev/null 2>&1
took=$(($(date +%s) - start))
if [ "$took" -lt 8 ]; then
    pass "docker compose stop game-day за $took с: SIGTERM дошёл до Java (ENTRYPOINT списком)"
else
    fail "stop занял $took с, а ENTRYPOINT списком должен закрываться сразу"
fi

section "Том переживает down, game-alive.sh без стенда — curl: (7)"
docker compose down >/dev/null 2>&1
expect_ok $? "docker compose down"
expect_contains "$(docker volume ls --format '{{.Name}}' 2>&1)" "$VOLUME" "после down том $VOLUME на месте"
out=$(stand/game-alive.sh 2>&1); code=$?
if [ "$code" -eq 1 ]; then pass "game-alive.sh: код 1"; else fail "game-alive.sh: код $code, ждали 1"; fi
expect_contains "$out" "curl: (7)" "curl: (7) — не подключился"
show "$out"
out=$(docker compose up -d --wait --wait-timeout 120 2>&1); code=$?
expect_ok "$code" "docker compose up -d — стенд снова поднят"
[ "$code" -eq 0 ] || show "$(tail -n 10 <<<"$out")"
count=$(incidents)
if [ "$count" = 2 ]; then
    pass "в журнале два «Брокера» — с прошлого подъёма и с этого"
else
    fail "в журнале «$count», ждали 2"
fi
show "$(incidents_table)"
expect_contains "$(docker compose logs game-day 2>&1)" 'Schema "game_day" is up to date. No migration necessary.' \
    "Flyway: эту базу он уже видел"

section "down -v: том удалён, база с нуля"
docker compose down -v >/dev/null 2>&1
expect_ok $? "docker compose down -v"
if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    fail "после down -v том $VOLUME остался"
else
    pass "после down -v тома $VOLUME нет"
fi
out=$(docker compose up -d --wait --wait-timeout 120 2>&1); code=$?
expect_ok "$code" "docker compose up -d после down -v"
count=$(incidents)
if [ "$count" = 1 ]; then pass "в журнале снова одно происшествие"; else fail "в журнале «$count», ждали 1"; fi
expect_contains "$(docker compose logs game-day 2>&1)" 'Successfully applied 1 migration to schema "game_day"' \
    "Flyway опять применил миграцию: том новый"

# Вариант образа с ENTRYPOINT строкой: собрать, запустить в сети стенда, дождаться старта, docker stop.
# Печатает, сколько секунд шёл stop; код 1 — не собрался или не поднялся, тогда печатает причину.
# Аргументы: имя варианта, строка ENTRYPOINT целиком.
entrypoint_stop() {
    local name=$1 line=$2 v i start started=""
    v=$(make_variant "entrypoint-$name")
    sed -i "s|^ENTRYPOINT .*|$line|" "$v/Dockerfile"
    if ! grep -qxF -- "$line" "$v/Dockerfile"; then echo "строка ENTRYPOINT не легла"; return 1; fi
    if ! (cd "$v" && docker build -q -t "game-day:$name" . >/dev/null 2>&1); then echo "образ не собрался"; return 1; fi
    if ! docker run -d --rm --name "game-day-$name" --network "$NETWORK" \
        -e SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/postgres \
        -e SPRING_DATASOURCE_USERNAME=postgres -e SPRING_DATASOURCE_PASSWORD="$DB_PASSWORD" \
        "game-day:$name" >/dev/null; then
        echo "docker run в сети $NETWORK не прошёл"
        return 1
    fi
    for ((i = 0; i < 120; i++)); do
        if grep -q "Started GameDayApplication" <<<"$(docker logs "game-day-$name" 2>&1)"; then
            started=yes
            break
        fi
        sleep 1
    done
    if [ -z "$started" ]; then
        echo "не поднялся за 120 с: $(docker logs "game-day-$name" 2>&1 | tail -n 5)"
        docker rm -f "game-day-$name" >/dev/null 2>&1
        return 1
    fi
    start=$(date +%s)
    docker stop "game-day-$name" >/dev/null
    echo $(($(date +%s) - start))
}

ARTICLE6=${ROOT:-}/articles/06-stand.md
section "ENTRYPOINT строкой, одна команда: sh в alpine заменяет себя Java — сигнал доходит"
if took=$(entrypoint_stop shell 'ENTRYPOINT java -jar /app/app.jar'); then
    if [ "$took" -lt 8 ]; then
        pass "docker stop за $took с: главный процесс — Java, SIGTERM дошёл"
    else
        fail "docker stop ждал $took с, а статья говорит: одна команда — сигнал доходит"
    fi
else
    fail "вариант ENTRYPOINT строкой: $took"
fi

section "ENTRYPOINT строкой с «; echo stopped»: главная — оболочка, Docker добивает Java через 10 с"
if [ -f "$ARTICLE6" ]; then
    expect_contains "$(cat "$ARTICLE6")" '`java -jar /app/app.jar; echo stopped`' "строка — та же, что в статье"
fi
if took=$(entrypoint_stop shell-tail 'ENTRYPOINT java -jar /app/app.jar; echo stopped'); then
    if [ "$took" -ge 9 ]; then
        pass "docker stop ждал $took с: оболочка сигнал не передала, Docker добил Java через 10 с"
    else
        fail "docker stop за $took с, а статья говорит: оболочка сигнал не передаст"
    fi
else
    fail "вариант с «; echo stopped»: $took"
fi

section "Том помнит пароль: новый пароль в .env — password authentication failed"
sed -i 's/^GAME_DAY_DB_PASSWORD=.*/GAME_DAY_DB_PASSWORD=changed-db-local/' .env
out=$(docker compose up -d 2>&1); code=$?
expect_ok "$code" "docker compose up -d с новым паролем в .env"
if logs=$(wait_log game-day 'password authentication failed for user "postgres"' 120); then
    pass "в логе game-day — password authentication failed for user \"postgres\""
else
    fail "в логе game-day нет password authentication failed"
    show "$(tail -n 20 <<<"$logs")"
fi
show "$(grep -m 1 -o 'FATAL: password authentication failed for user "postgres"' <<<"$logs")"
cp .env.example .env
out=$(docker compose up -d --wait --wait-timeout 120 2>&1); code=$?
expect_ok "$code" "прежний пароль в .env — стенд поднялся на том же томе"
sed -i 's/^GAME_DAY_DB_PASSWORD=.*/GAME_DAY_DB_PASSWORD=changed-db-local/' .env
docker compose down -v >/dev/null 2>&1
out=$(stand/game-up.sh 2>&1); code=$?
expect_ok "$code" "новый пароль после down -v — том создан заново и принял его"
cp .env.example .env
docker compose down -v >/dev/null 2>&1

section "Без стоп-слова: предупреждение Compose и APPLICATION FAILED TO START"
sed -i 's/^GAME_DAY_STOP_WORD=/# &/' .env
out=$(docker compose up -d 2>&1)
expect_regex "$out" 'GAME_DAY_STOP_WORD.{0,2} variable is not set' "Compose предупредил о незаданной GAME_DAY_STOP_WORD"
show "$(grep 'variable is not set' <<<"$out")"
if logs=$(wait_log game-day "APPLICATION FAILED TO START" 120); then
    pass "приложение не поднялось: APPLICATION FAILED TO START"
else
    fail "в логе game-day нет APPLICATION FAILED TO START"
fi
expect_contains "$logs" "stopWord" "в блоке — stopWord"
show "$(grep -A 10 'APPLICATION FAILED TO START' <<<"$logs")"
cp .env.example .env
docker compose down -v >/dev/null 2>&1

section "Без правила health: Docker спрашивает без пароля, получает 401 — стенд unhealthy"
NOHEALTH=$(make_variant no-health-stand)
grep -vF -- "$HEALTH_RULE" "$SECURITY" >"$NOHEALTH/$SECURITY"
sed -i 's|image: game-day:local|image: game-day:nohealth|' "$NOHEALTH/compose.yaml"
out=$(cd "$NOHEALTH" && stand/game-up.sh 2>&1); code=$?
expect_failed "$code" "stand/game-up.sh без правила health"
expect_contains "$out" "container $APP_CONTAINER is unhealthy" "Compose: container $APP_CONTAINER is unhealthy"
show "$(grep -m 1 'is unhealthy' <<<"$out")"
expect_regex "$(cd "$NOHEALTH" && docker compose ps 2>&1)" "^$APP_CONTAINER .*\(unhealthy\)" \
    "docker compose ps: game-day — (unhealthy)"
expect_regex "$(status_of "$(http "$STAND/actuator/health")")" '^HTTP/1\.1 401 ?$' \
    "приложение работает, а health без входа — 401"
(cd "$NOHEALTH" && docker compose down -v >/dev/null 2>&1)
docker image rm game-day:nohealth game-day:shell >/dev/null 2>&1

section "Первоисточники открываются"
for link in https://docs.docker.com/reference/dockerfile/ \
    https://docs.docker.com/build/building/best-practices/ \
    https://docs.docker.com/reference/compose-file/services/ \
    https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/ \
    https://hub.docker.com/_/postgres \
    https://docs.spring.io/spring-boot/reference/actuator/endpoints.html \
    https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done

# Убрать стенд, контейнеры и базу, если что-то оборвалось раньше; последняя команда — с кодом 0.
cleanup
