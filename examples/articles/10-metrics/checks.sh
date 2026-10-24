# Статья 10 «Метрики: счётчик, датчик, таймер, теги» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 9: Postgres, JPA, Flyway, веб, охрана, Actuator, стенд, объекты-значения, серьёзность.
# Тесты статьи уже прошли в mvn verify: IncidentMetricsTest на SimpleMeterRegistry, IncidentLogTest
# и IncidentLogAgeTest с пятой заглушкой, IncidentLogIT — журнал с настоящим IncidentMetrics из MeterRegistry Boot.
# Здесь — лист сборки статьи (Micrometer 1.17 из BOM Boot 4.1; micrometer-core приносит Actuator;
# @AutoConfigureMetrics вместо @AutoConfigureObservability; countByFixedAtIsNull в SQL; точный вид
# /actuator/prometheus — 2 или 2.0, есть ли _max) и то, что статья обещает словами: имена и числа в Prometheus,
# get/find, датчик спрашивает заново, registry.gauge с числом, отрицательная длительность, слабая ссылка
# (WeakDemo); в песочнице — 401/403/200 у ручки метрик, ряды с нулём, датчик против счётчика после вставки в psql
# и перезапуска, метрики Boot, 404 без include, health пропадает без health в include, 403 без правила, NaN без базы.

JAR=target/game-day-0.0.1-SNAPSHOT.jar
DB=game-day-db
PASSWORD=game-day-local
PORT=${GAME_DAY_DB_PORT:-5432}
IMAGE=postgres:17-alpine
APP_PORT=${GAME_DAY_APP_PORT:-8080}
LOCAL=http://127.0.0.1:$APP_PORT
METRICS=$LOCAL/actuator/prometheus
ADMIN=admin:admin-local
VIEWER=viewer:viewer-local
SECURITY=src/main/java/example/gameday/SecurityConfig.java
PROMETHEUS_RULE='.requestMatchers(HttpMethod.GET, "/actuator/prometheus").hasRole("admin")'
APP_PID=""
APP_LOG=""
classpath >/dev/null
DEPS=$(cat target/cp.txt)
PROBE="$VARIANTS/$(basename "$PWD")-probe"

# Строки журнала на ручке сразу после первого запуска — как в статье, часть 3 «Посмотри вживую».
FIRST_SCRAPE='gameday_incident_fix_duration_seconds_count 0
gameday_incident_fix_duration_seconds_sum 0.0
gameday_incident_fix_duration_seconds_max 0.0
gameday_incidents_open 1.0
gameday_incidents_reported_total{severity="critical"} 0.0
gameday_incidents_reported_total{severity="high"} 0.0
gameday_incidents_reported_total{severity="low"} 1.0'

# Фрагмент «после игры» — как в статье, часть 3 «Что лежит на ручке»; строки — из разных мест ответа.
AFTER_GAME='# HELP gameday_incidents_open Происшествия, открытые прямо сейчас
# TYPE gameday_incidents_open gauge
gameday_incidents_open 2.0
gameday_incidents_reported_total{severity="critical"} 3.0
gameday_incidents_reported_total{severity="high"} 0.0
gameday_incidents_reported_total{severity="low"} 1.0
gameday_incident_fix_duration_seconds_count 2
gameday_incident_fix_duration_seconds_sum 2400.0
gameday_incident_fix_duration_seconds_max 1800.0'

# Вставка мимо журнала — команда статьи, буква в букву.
INSERT_SQL="INSERT INTO game_day.incident (title, detected_at, duty_name) VALUES ('лента стоит', now(), 'duty-2')"

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

# Есть ли строка целиком. Аргументы: текст, строка, пояснение.
expect_line() { if grep -qxF -- "$2" <<<"$1"; then pass "$3"; else fail "$3: нет строки «$2»"; fi; }

# Каждая строка блока есть целиком. Аргументы: текст, блок, пояснение.
expect_lines() {
    local line missing=""
    while IFS= read -r line; do
        grep -qxF -- "$line" <<<"$1" || missing+="«$line» "
    done <<<"$2"
    if [ -z "$missing" ]; then pass "$3"; else fail "$3: нет строк $missing"; fi
}

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

# Песочница, как в статье 5: java -jar (или классы варианта), адрес базы — переменными окружения; в фоне,
# лог — в target/app-<имя>.log. Готово, когда main напечатал «атакующих …»: Tomcat к этому времени слушает порт.
# Аргументы: имя, .jar или каталог классов, дальше — аргументы приложения. Код 1 — не дождались.
app_start() {
    local name=$1 what=$2 i
    shift 2
    APP_LOG="target/app-$name.log"
    local cmd=(java "${UTF8[@]}")
    if [[ $what == *.jar ]]; then
        cmd+=(-jar "$what")
    else
        cmd+=(-cp "$what:$DEPS" example.gameday.GameDayApplication)
    fi
    env SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:$PORT/postgres" \
        SPRING_DATASOURCE_USERNAME=postgres SPRING_DATASOURCE_PASSWORD="$PASSWORD" \
        "${cmd[@]}" --server.port="$APP_PORT" "$@" >"$APP_LOG" 2>&1 &
    APP_PID=$!
    for ((i = 0; i < 180; i++)); do
        grep -qE 'атакующих [0-9]' "$APP_LOG" && return 0
        kill -0 "$APP_PID" 2>/dev/null || return 1
        sleep 1
    done
    return 1
}

# Остановить приложение, как Ctrl+C; не закрылось за 60 с — добить.
app_stop() {
    [ -n "$APP_PID" ] || return 0
    kill "$APP_PID" 2>/dev/null
    local i
    for ((i = 0; i < 60; i++)); do
        kill -0 "$APP_PID" 2>/dev/null || break
        sleep 1
    done
    kill -9 "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null
    APP_PID=""
    return 0
}

# curl -i, как в статье; \r из заголовков убираем, чтобы сверять построчно.
http() { curl -sS -i -m 60 "$@" 2>&1 | tr -d '\r'; }
status_of() { head -n 1 <<<"$1"; }
body_of() { sed '1,/^$/d' <<<"$1"; }

# Ответ ручки метрик под admin — как curl -s -u admin:admin-local в статье. $1 — сколько ждать, секунд.
scrape() { curl -sS -m "${1:-60}" -u "$ADMIN" "$METRICS" 2>&1; }

# Строки журнала — как grep '^gameday' в статье.
gameday() { grep '^gameday' <<<"$1"; }

cleanup() {
    app_stop
    db_down
    return 0
}
trap cleanup EXIT

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok example.gameday.journal.IncidentMetricsTest 2
suite_ok example.gameday.journal.IncidentLogTest 1
suite_ok example.gameday.journal.IncidentLogAgeTest 1
suite_green example.gameday.journal.IncidentLogIT "журнал собран Spring с настоящим IncidentMetrics"
for cls in IncidentTest IncidentTableIT IncidentRepositoryIT IncidentPagesIT IncidentListServiceTest IncidentListIT \
    IncidentAgeIT IncidentColumnsIT SeverityConverterTest; do
    suite_green "example.gameday.journal.$cls"
done
suite_green example.gameday.GameDayApplicationTests "приложение с IncidentMetrics поднимается"
suite_green example.gameday.PerimeterTest "ручку метрик тест периметра не видит — строка в DECLARED не нужна"
expect_contains "$(cat pom.xml)" "<artifactId>micrometer-registry-prometheus</artifactId>" \
    "в pom.xml — micrometer-registry-prometheus, без <version>"
expect_contains "$(cat "$SECURITY")" "$PROMETHEUS_RULE" "в SecurityConfig — GET /actuator/prometheus только admin"

section "Версии из BOM Boot 4.1: Micrometer 1.17; micrometer-core приносит Actuator"
jars=$(tr ':' '\n' <<<"$DEPS" | sed 's#.*/##')
expect_regex "$jars" '^micrometer-core-1\.17\.[0-9]+\.jar$' "статья: «в Boot 4.1 это Micrometer 1.17»"
core=$(grep -m 1 -oE '^micrometer-core-[0-9][0-9A-Za-z.-]*\.jar$' <<<"$jars" | sed -e 's/^micrometer-core-//' -e 's/\.jar$//')
expect_contains "$jars" "micrometer-registry-prometheus-$core.jar" \
    "micrometer-registry-prometheus той же версии, что micrometer-core ($core): версию подставил <parent>"
note "$(grep -E '^(micrometer-|prometheus-metrics-)' <<<"$jars" | tr '\n' ' ')"
note "$(java -version 2>&1 | head -n 1)"
v=$(make_variant after-9)
perl -0pi -e 's#\s*<dependency>\s*<groupId>io\.micrometer</groupId>\s*<artifactId>micrometer-registry-prometheus</artifactId>.*?</dependency>##s' \
    "$v/pom.xml"
expect_not_contains "$(cat "$v/pom.xml")" "<artifactId>micrometer-registry-prometheus</artifactId>" \
    "вариант pom.xml без реестра для Prometheus — как после статьи 9"
(cd "$v" && mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=cp.txt -Dmdep.includeScope=runtime >/dev/null 2>&1)
expect_regex "$(tr ':' '\n' <"$v/cp.txt" 2>/dev/null | sed 's#.*/##')" '^micrometer-core-' \
    "после статьи 9 micrometer-core уже на пути классов — в pom.xml для него ничего не добавляют"
tree=$(cd "$v" && mvn -B -ntp dependency:tree -Dincludes=io.micrometer:micrometer-core 2>&1)
show "$(grep -E '[+\\]- ' <<<"$tree" | sed 's/^\[INFO\] //')"
v=$(make_variant no-actuator)
perl -0pi -e 's#\s*<dependency>\s*<groupId>io\.micrometer</groupId>\s*<artifactId>micrometer-registry-prometheus</artifactId>.*?</dependency>##s' \
    "$v/pom.xml"
perl -0pi -e 's#\s*<dependency>\s*<groupId>org\.springframework\.boot</groupId>\s*<artifactId>spring-boot-starter-actuator</artifactId>\s*</dependency>##s' \
    "$v/pom.xml"
expect_not_contains "$(cat "$v/pom.xml")" "<artifactId>spring-boot-starter-actuator</artifactId>" "вариант pom.xml и без Actuator"
(cd "$v" && mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=cp.txt -Dmdep.includeScope=runtime >/dev/null 2>&1)
if [ ! -s "$v/cp.txt" ]; then
    fail "вариант без Actuator: путь классов не собрался"
elif grep -q 'micrometer-core-' "$v/cp.txt"; then
    fail "micrometer-core есть и без Actuator — статья говорит, что его приносит Actuator"
else
    pass "без Actuator micrometer-core нет — Micrometer приезжает со стартером Actuator"
fi

section "⚠️ @AutoConfigureObservability — Boot 3; в Boot 4 — @AutoConfigureMetrics из spring-boot-micrometer-metrics-test"
boot=$(sed -n '/<parent>/,/<\/parent>/s#.*<version>\(.*\)</version>.*#\1#p' pom.xml)
rm -rf target/probe-jars
out=$(mvn -B -q -ntp dependency:copy -Dartifact="org.springframework.boot:spring-boot-micrometer-metrics-test:$boot" \
    -DoutputDirectory=target/probe-jars 2>&1); code=$?
expect_ok "$code" "модуль org.springframework.boot:spring-boot-micrometer-metrics-test:$boot есть"
[ "$code" -eq 0 ] || show "$(tail -n 20 <<<"$out")"
list=$(for jar_file in target/probe-jars/*.jar; do jar tf "$jar_file"; done 2>&1)
expect_regex "$list" '/AutoConfigureMetrics\.class$' "в модуле — аннотация @AutoConfigureMetrics"
show "$(grep -E '/AutoConfigure(Metrics|Observability)\.class$' <<<"$list")"
expect_not_contains "$list" "AutoConfigureObservability" "@AutoConfigureObservability в модуле нет"
mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp-test.txt -Dmdep.includeScope=test >/dev/null
found=""
while IFS= read -r jar_file; do
    [[ $jar_file == *.jar ]] || continue
    # Без трубы в grep -q: при pipefail ранний выход grep обрывает jar tf, и проверка молча зеленеет.
    if grep -q 'AutoConfigureObservability' < <(jar tf "$jar_file" 2>/dev/null); then found+="$jar_file "; fi
done < <(tr ':' '\n' <target/cp-test.txt | grep '/org/springframework/boot/')
if [ -z "$found" ]; then
    pass "в библиотеках Boot на пути классов тестов @AutoConfigureObservability нет"
else
    fail "@AutoConfigureObservability нашлась: $found"
fi

section "Проба Micrometer: формат Prometheus, датчик спрашивает заново, get и find, ловушки"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/MetricsProbe.java" <<'EOF'
package example.gameday.journal;

import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.prometheusmetrics.PrometheusConfig;
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry;

import java.lang.reflect.Proxy;
import java.time.Duration;
import java.util.EnumMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

// Проба для checks.sh статьи 10: печатает то, что статья обещает словами о Micrometer. В статью не идёт.
public class MetricsProbe {

    // Сколько «открыто» — как ответило бы хранилище; хранилище — заглушка без Mockito.
    static final AtomicLong OPEN = new AtomicLong();
    static final IncidentRepository INCIDENTS = (IncidentRepository) Proxy.newProxyInstance(
            IncidentRepository.class.getClassLoader(), new Class<?>[] {IncidentRepository.class},
            (proxy, method, args) -> switch (method.getName()) {
                case "countByFixedAtIsNull" -> OPEN.get();
                case "hashCode" -> System.identityHashCode(proxy);
                case "equals" -> proxy == args[0];
                case "toString" -> "хранилище пробы";
                default -> throw new UnsupportedOperationException(method.getName());
            });

    public static void main(String[] args) {
        PrometheusMeterRegistry prometheus = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
        IncidentMetrics game = new IncidentMetrics(prometheus, INCIDENTS);
        OPEN.set(2);
        for (int i = 0; i < 3; i++) {
            game.reported(Severity.CRITICAL);
        }
        game.reported(Severity.LOW);
        game.fixed(Duration.ofMinutes(10));
        game.fixed(Duration.ofMinutes(30));
        System.out.println("=== ответ ручки после игры");
        System.out.print(prometheus.scrape());
        System.out.println("=== конец ответа");

        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        IncidentMetrics metrics = new IncidentMetrics(registry, INCIDENTS);
        System.out.println("рядов gameday.incidents.reported сразу: "
                + registry.find("gameday.incidents.reported").counters().size());
        OPEN.set(3);
        double before = registry.get("gameday.incidents.open").gauge().value();
        OPEN.set(1);
        double after = registry.get("gameday.incidents.open").gauge().value();
        System.out.println("датчик с функцией: " + before + " → " + after);

        OPEN.set(3);
        registry.gauge("probe.open.once", INCIDENTS.countByFixedAtIsNull());
        OPEN.set(20);
        System.out.println("датчик с числом: " + registry.get("probe.open.once").gauge().value()
                + ", а открытых уже " + OPEN.get());

        AtomicInteger number = new AtomicInteger(0);
        AtomicInteger returned = registry.gauge("probe.open.atomic", number);
        System.out.println("registry.gauge вернул тот же объект: " + (returned == number));

        try {
            registry.get("gameday.incidents.lost").counter();
            System.out.println("get без метрики: вернул счётчик");
        } catch (RuntimeException e) {
            System.out.println("get без метрики: " + e.getClass().getSimpleName());
        }
        System.out.println("find без ряда: "
                + registry.find("gameday.incidents.reported").tag("severity", "medium").counter());

        Timer timer = registry.get("gameday.incident.fix.duration").timer();
        metrics.fixed(Duration.ofMinutes(-5));
        System.out.println("отрицательная длительность: событий " + timer.count()
                + ", времени " + timer.totalTime(TimeUnit.SECONDS));

        try {
            metrics.reported(null);
            System.out.println("reported(null): без исключения");
        } catch (NullPointerException e) {
            System.out.println("reported(null): " + e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        System.out.println("EnumMap.get(null): " + new EnumMap<Severity, String>(Severity.class).get(null));
        System.out.println("--- конец");
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "target/classes:$DEPS" "$PROBE"/src/*.java 2>&1)
expect_ok $? "javac пробы"
show "$out"
probe=$(java "${UTF8[@]}" -cp "$PROBE/classes:target/classes:$DEPS" example.gameday.journal.MetricsProbe 2>&1)
expect_contains "$probe" "--- конец" "проба дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"
answer=$(sed -n '/^=== ответ ручки после игры$/,/^=== конец ответа$/p' <<<"$probe")
expect_lines "$answer" "$AFTER_GAME" "фрагмент «после игры» — каждая строка как в статье"
expect_line "$answer" "gameday_incident_fix_duration_seconds_count 2" "число событий таймера — целое, 2, а не 2.0"
expect_line "$answer" "gameday_incident_fix_duration_seconds_max 1800.0" "_max есть: самое долгое — 1800.0 секунд"
expect_line "$answer" "gameday_incident_fix_duration_seconds_sum 2400.0" "минуты таймер отдал секундами: 40 мин — 2400.0"
expect_not_contains "$answer" "gameday.incidents" "точек в именах нет — реестр поменял их на подчёркивания"
show "$(grep -E 'gameday' <<<"$answer")"
expect_contains "$probe" "рядов gameday.incidents.reported сразу: 3" "три ряда severity — сразу, с нулём"
expect_contains "$probe" "датчик с функцией: 3.0 → 1.0" "датчик спрашивает функцию при каждом чтении"
expect_contains "$probe" "датчик с числом: 3.0, а открытых уже 20" \
    "registry.gauge(имя, число): число посчитано при регистрации — датчик его и показывает"
expect_contains "$probe" "registry.gauge вернул тот же объект: true" "registry.gauge(…, new AtomicInteger(0)) вернул тот же объект"
expect_regex "$probe" '^get без метрики: [A-Za-z]+Exception$' "registry.get без метрики — исключение"
expect_contains "$probe" "find без ряда: null" "registry.find(…).tag(…).counter() без ряда — null"
expect_contains "$probe" "отрицательная длительность: событий 0, времени 0.0" \
    "отрицательную длительность таймер молча пропустил — ни ошибки, ни события"
expect_contains "$probe" "reported(null): NullPointerException: метрика журнала: нет серьёзности" \
    "requireNonNull: то же NullPointerException, но с нашим текстом"
expect_contains "$probe" "EnumMap.get(null): null" "EnumMap.get(null) возвращает null, а не бросает"
show "$(grep -E '^(рядов|датчик|registry|get|find|отрицательная|reported|EnumMap)' <<<"$probe")"

section "⚠️ Слабая ссылка: java WeakDemo.java"
expect_file WeakDemo.java
out=$(java "${UTF8[@]}" WeakDemo.java 2>&1); code=$?
expect_ok "$code" "java WeakDemo.java — Java сама скомпилировала один файл"
expect_line "$out" "держим:    3.0" "объект, который держит переменная, пережил сборку мусора"
expect_line "$out" "не держим: NaN" "объект, который не держит никто, убран — NaN"
show "$out"

section "Песочница: ручка метрик — 401 без входа, 403 под viewer, 200 под admin; ряды с нулём"
if db_up; then
    pass "база на минуту: docker run $IMAGE на 127.0.0.1:$PORT, как в статье 3а"
else
    fail "база в контейнере не поднялась"
fi
if app_start first "$JAR" --spring.jpa.show-sql=true; then
    out=$(http "$METRICS")
    expect_regex "$(status_of "$out")" '^HTTP/1\.1 401 ?$' "curl -i /actuator/prometheus без входа — 401"
    expect_regex "$out" '^WWW-Authenticate: Basic realm="Realm", charset="UTF-8"$' "…с просьбой войти по Basic"
    show "$(head -n 2 <<<"$out")"
    expect_regex "$(status_of "$(http -u "$VIEWER" "$METRICS")")" '^HTTP/1\.1 403 ?$' "под viewer — 403"
    out=$(http -u "$ADMIN" "$METRICS")
    expect_regex "$(status_of "$out")" '^HTTP/1\.1 200 ?$' "под admin — 200"
    note "$(grep -i '^Content-Type:' <<<"$out")"
    body=$(body_of "$out")
    lines=$(gameday "$body")
    expect_lines "$lines" "$FIRST_SCRAPE" "grep '^gameday': каждая строка — как в статье"
    if [ "$lines" = "$FIRST_SCRAPE" ]; then
        pass "grep '^gameday' — ровно семь строк статьи и в том же порядке"
    else
        fail "grep '^gameday' — не ровно блок статьи (лишние строки или другой порядок)"
    fi
    show "$lines"
    expect_line "$body" "# HELP gameday_incidents_open Происшествия, открытые прямо сейчас" \
        "# HELP — описание из .description(…)"
    expect_line "$body" "# TYPE gameday_incidents_open gauge" "# TYPE … gauge — датчик"
    show "$(grep -E '^# (HELP|TYPE) gameday_incidents_open ' <<<"$body")"
    out=$(curl -sS -m 30 "$LOCAL/actuator/health" 2>&1)
    expect_contains "$out" '"status":"UP"' "/actuator/health без входа — по-прежнему UP"
    expect_regex "$(status_of "$(http -u "$ADMIN" "$LOCAL/actuator")")" '^HTTP/1\.1 403 ?$' \
        "/actuator под admin — 403: правило ровно на один адрес, остальное закрыто"
    sql=$(grep -m 1 -E '^Hibernate: select count\(' "$APP_LOG")
    expect_regex "$sql" '^Hibernate: select count\(.*\) from game_day\.incident .*where .*fixed_at is null' \
        "countByFixedAtIsNull: Spring Data вывел запрос по имени — select count(…) … where fixed_at is null"
    show "$sql"

    section "Песочница: вставка мимо журнала — датчик видит, счётчик нет"
    out=$(docker exec "$DB" psql -U postgres -c "$INSERT_SQL" 2>&1)
    expect_contains "$out" "INSERT 0 1" "docker exec … psql -c \"INSERT …\" — строка легла, DEFAULT дал серьёзность"
    body=$(scrape)
    expect_line "$body" "gameday_incidents_open 2.0" "датчик спросил базу заново, без перезапуска: 2.0"
    expect_line "$body" 'gameday_incidents_reported_total{severity="low"} 1.0' "low остался 1.0 — считать было некому"
    show "$(gameday "$body")"
else
    fail "песочница не поднялась"
    show "$(tail -n 30 "$APP_LOG")"
fi
app_stop

section "Песочница: перезапуск — счётчик с нуля, датчик из базы; метрики Boot"
if app_start second "$JAR"; then
    body=$(scrape)
    expect_line "$body" 'gameday_incidents_reported_total{severity="low"} 1.0' \
        "после перезапуска low — опять 1.0: счётчик начал с нуля, запуск записал «Брокера»"
    expect_line "$body" "gameday_incidents_open 3.0" "открытых — 3.0: два из базы и новый"
    show "$(gameday "$body")"
    curl -sS -m 30 -o /dev/null -u "$ADMIN" "$LOCAL/game-day/incidents"
    body=$(scrape)
    expect_regex "$body" '^http_server_requests_seconds_count\{[^}]*,uri="/game-day/incidents"\} 1$' \
        "таймер Boot: http_server_requests_seconds_count{…,uri=\"/game-day/incidents\"} 1"
    expect_regex "$body" '^jvm_memory_used_bytes\{' "память JVM — jvm_memory_used_bytes"
    show "$(grep -E '^http_server_requests_seconds_(count|sum|max)\{[^}]*uri="/game-day/incidents"' <<<"$body")"

    section "Без базы: датчик — NaN, счётчики на месте, в логе — предупреждение Micrometer"
    docker stop "$DB" >/dev/null 2>&1
    expect_ok $? "docker stop $DB"
    start=$(date +%s)
    body=$(scrape 180)
    took=$(($(date +%s) - start))
    expect_line "$body" "gameday_incidents_open NaN" "база остановлена — gameday_incidents_open NaN, а не 0"
    expect_line "$body" 'gameday_incidents_reported_total{severity="low"} 1.0' "счётчики живут в памяти и на месте"
    expect_line "$body" 'gameday_incidents_reported_total{severity="critical"} 0.0' "…critical 0.0"
    expect_line "$body" "gameday_incident_fix_duration_seconds_count 0" "…строки таймера прежние"
    note "ответ пришёл через $took с: сколько ждать без базы, статья не обещает"
    show "$(grep -E '^gameday_incidents' <<<"$body")"
    log=$(cat "$APP_LOG")
    expect_contains "$log" "Failed to apply the value function for the gauge 'gameday.incidents.open'" \
        "в логе — Failed to apply the value function for the gauge 'gameday.incidents.open'"
    show "$(grep -m 1 -o "Failed to apply the value function for the gauge 'gameday.incidents.open'.\{0,1\}" <<<"$log")"
else
    fail "песочница не поднялась после перезапуска"
    show "$(tail -n 30 "$APP_LOG")"
fi
app_stop

section "Что будет, если: без prometheus в include — 404; без health в include — health пропал"
db_up || fail "база в контейнере не поднялась"
if app_start no-include "$JAR" --management.endpoints.web.exposure.include=health; then
    expect_regex "$(status_of "$(http -u "$ADMIN" "$METRICS")")" '^HTTP/1\.1 404 ?$' \
        "include: health — под admin /actuator/prometheus 404: охрана пропустила, а ручки нет"
    expect_regex "$(status_of "$(http "$METRICS")")" '^HTTP/1\.1 401 ?$' "…без входа — всё равно 401: охрана раньше"
else
    fail "вариант include: health не поднялся"
    show "$(tail -n 30 "$APP_LOG")"
fi
app_stop
if app_start only-prometheus "$JAR" --management.endpoints.web.exposure.include=prometheus; then
    expect_regex "$(status_of "$(http "$LOCAL/actuator/health")")" '^HTTP/1\.1 404 ?$' \
        "include: prometheus — /actuator/health 404: список заменяет умолчание, а не дописывается"
    expect_regex "$(status_of "$(http -u "$ADMIN" "$METRICS")")" '^HTTP/1\.1 200 ?$' "…а метрики под admin — 200"
else
    fail "вариант include: prometheus не поднялся"
    show "$(tail -n 30 "$APP_LOG")"
fi
app_stop

section "Что будет, если: без правила в SecurityConfig — denyAll, под admin 403"
v=$(make_variant no-prometheus-rule)
grep -vF -- "$PROMETHEUS_RULE" "$SECURITY" >"$v/$SECURITY"
if cmp -s "$SECURITY" "$v/$SECURITY"; then fail "из SecurityConfig варианта правило не убралось"; fi
rm -rf "$v/classes" && cp -r target/classes "$v/classes"
if (cd "$v" && javac -encoding UTF-8 -proc:none -parameters -nowarn -d classes -cp "classes:$DEPS" "$SECURITY") \
    >"$v/javac.log" 2>&1; then
    if app_start no-rule "$v/classes"; then
        out=$(http -u "$ADMIN" "$METRICS")
        expect_regex "$(status_of "$out")" '^HTTP/1\.1 403 ?$' "без правила под admin — 403: сработал denyAll"
        expect_regex "$(status_of "$(http "$METRICS")")" '^HTTP/1\.1 401 ?$' "…без входа — 401"
        show "$(status_of "$out")"
    else
        fail "вариант без правила не поднялся"
        show "$(tail -n 30 "$APP_LOG")"
    fi
    app_stop
else
    fail "вариант без правила не скомпилировался"
    show "$(cat "$v/javac.log")"
fi
db_down

section "Первоисточники открываются"
for link in https://docs.micrometer.io/micrometer/reference/concepts/gauges.html \
    https://docs.micrometer.io/micrometer/reference/concepts/timers.html \
    https://docs.micrometer.io/micrometer/reference/implementations/prometheus.html \
    https://docs.spring.io/spring-boot/reference/actuator/endpoints.html \
    https://docs.spring.io/spring-boot/reference/actuator/metrics.html \
    https://prometheus.io/docs/practices/naming/ \
    https://prometheus.io/docs/concepts/jobs_instances/; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done

# Убрать приложение и базу, если что-то оборвалось раньше; последняя команда — с кодом 0.
cleanup
