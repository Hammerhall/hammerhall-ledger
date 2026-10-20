# Статья 6 «Стенд своими руками» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
# Закрывает лист сборки статьи: образ на alpine, health с groups, compose up --wait,
# exec -T, стоп-слово, коды выхода скриптов.

HEALTH_JSON='{"groups":["liveness","readiness"],"status":"UP"}'
JAR=target/game-day-0.0.1-SNAPSHOT.jar

cleanup() {
    docker compose down -v >/dev/null 2>&1
    docker rm -f game-day-try game-day-shell >/dev/null 2>&1
    return 0
}
cleanup

section "Веб и Actuator: приложение не завершается и отвечает на health"
java "${UTF8[@]}" -jar "$JAR" >target/app.log 2>&1 &
app=$!
if out=$(wait_http http://127.0.0.1:8080/actuator/health 90); then
    pass "отвечает на 127.0.0.1:8080/actuator/health"
    expect_contains "$out" "$HEALTH_JSON" "ответ — как в статье"
    show "$out"
else
    fail "не ответило на /actuator/health за 90 с"
    show "$(tail -n 30 target/app.log)"
fi
kill "$app" 2>/dev/null
wait "$app" 2>/dev/null

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

section "Контейнер руками: run, logs, health, stop"
docker run -d --rm --name game-day-try -p 127.0.0.1:8088:8080 game-day:local >/dev/null
if out=$(wait_http http://127.0.0.1:8088/actuator/health 90); then
    expect_contains "$out" '"status":"UP"' "curl -fsS на 127.0.0.1:8088 — status UP"
else
    fail "контейнер не ответил на 127.0.0.1:8088"
fi
expect_contains "$(docker logs game-day-try 2>&1)" "атакующих 2" "в логе «атакующих 2» — профиль stand не включён"
start=$(date +%s)
docker stop game-day-try >/dev/null
took=$(($(date +%s) - start))
if [ "$took" -lt 8 ]; then
    pass "docker stop за $took с: SIGTERM дошёл до Java (ENTRYPOINT списком)"
else
    fail "docker stop занял $took с, а ENTRYPOINT списком должен закрываться сразу"
fi

section "ENTRYPOINT строкой — сигнал до Java не доходит"
v=$(make_variant entrypoint-string)
sed -i 's|^ENTRYPOINT .*|ENTRYPOINT java -jar /app/app.jar|' "$v/Dockerfile"
if (cd "$v" && docker build -q -t game-day:shell . >/dev/null 2>&1); then
    docker run -d --rm --name game-day-shell game-day:shell >/dev/null
    for _ in $(seq 60); do
        docker logs game-day-shell 2>&1 | grep -q "Started GameDayApplication" && break
        sleep 1
    done
    start=$(date +%s)
    docker stop game-day-shell >/dev/null
    took=$(($(date +%s) - start))
    if [ "$took" -ge 9 ]; then
        pass "docker stop ждал $took с — Docker добил процесс через 10 с, как в статье"
    else
        fail "docker stop за $took с: оболочка передала сигнал — статью поправить"
    fi
else
    fail "вариант с ENTRYPOINT строкой не собрался"
fi

section "compose и скрипты: поднять стенд"
cp .env.example .env
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
expect_contains "$(docker compose ps 2>&1)" "(healthy)" "docker compose ps — (healthy)"
expect_contains "$(docker compose logs game-day 2>&1)" "атакующих 4" "в логе «атакующих 4» — профиль stand"

section "Сеть изнутри: имя службы, а не 127.0.0.1:8088"
out=$(docker compose exec -T game-day wget -qO- http://game-day:8080/actuator/health 2>&1); code=$?
expect_ok "$code" "exec -T: wget по game-day:8080"
expect_contains "$out" '"status":"UP"' "status UP по имени службы"
out=$(docker compose exec -T game-day wget -qO- http://127.0.0.1:8088/actuator/health 2>&1); code=$?
expect_failed "$code" "127.0.0.1:8088 изнутри контейнера"
show "$out"

section "Стенд снесён — game-alive.sh честно падает"
docker compose down >/dev/null 2>&1
out=$(stand/game-alive.sh 2>&1); code=$?
if [ "$code" -eq 1 ]; then pass "game-alive.sh: код 1"; else fail "game-alive.sh: код $code, ждали 1"; fi
expect_contains "$out" "curl: (7)" "curl: (7) — не подключился"
show "$out"

section "Без стоп-слова: предупреждение Compose и APPLICATION FAILED TO START"
mv .env .env.off
out=$(docker compose up -d 2>&1)
expect_contains "$out" "variable is not set" "Compose предупредил о пустой переменной"
show "$(grep 'variable is not set' <<<"$out")"
logs=""
for _ in $(seq 60); do
    logs=$(docker compose logs game-day 2>&1)
    grep -q "APPLICATION FAILED TO START" <<<"$logs" && break
    sleep 1
done
expect_contains "$logs" "APPLICATION FAILED TO START" "приложение не поднялось"
expect_contains "$logs" "stopWord" "в блоке — stopWord"
show "$(grep -A 10 'APPLICATION FAILED TO START' <<<"$logs")"
mv .env.off .env

cleanup
