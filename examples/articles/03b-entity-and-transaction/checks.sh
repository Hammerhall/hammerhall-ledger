# Статья 3б «Данные, часть 2: сущность, хранилище, транзакция» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Тесты статьи уже прошли в mvn verify: IncidentTest, IncidentRepositoryIT и IncidentLogIT на Postgres
# из Testcontainers, IncidentTableIT из статьи 3а — со стартером JPA вместо JDBC. Здесь — лист сборки
# статьи (сверка схемы, методы по имени и опечатка, AssertJ и JUnit 6, второй бин Clock, два импорта
# Transactional, наследник от Hibernate, покрытие конструктора для JPA, транзакция теста) и то, что
# статья обещает словами: запуск пишет в базу, ошибки старта и компиляции, откат, @DataJpaTest в Boot 4.

JAR=target/game-day-0.0.1-SNAPSHOT.jar
DB=game-day-db
PASSWORD=game-day-local
PORT=${GAME_DAY_DB_PORT:-5432}
IMAGE=postgres:17-alpine
MAIN=src/main/java/example/gameday/journal
TEST=src/test/java/example/gameday/journal
BASE=../03a-table-and-migration                 # пример статьи 3а: старый журнал и IncidentLogTest
JACOCO=org.jacoco:jacoco-maven-plugin:0.8.15
DB_TESTS='GameDayApplicationTests,IncidentTableIT,IncidentRepositoryIT,IncidentLogIT'

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

# psql внутри контейнера; SQL — со стандартного ввода, как если бы его печатали после postgres=#.
psql_in() { docker exec -i "$DB" psql -X -U postgres 2>&1; }

# Приложение, как в статье 3а: адрес базы — переменными окружения. Аргумент — другой .jar (вариант).
app() {
    env SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:$PORT/postgres" \
        SPRING_DATASOURCE_USERNAME=postgres SPRING_DATASOURCE_PASSWORD="$PASSWORD" \
        timeout 180 java "${UTF8[@]}" -jar "${1:-$JAR}" 2>&1
}

# Собрать .jar варианта без тестов; лог — в mvn.log варианта.
variant_jar() { (cd "$1" && mvn -B -q -ntp package -DskipTests) >"$1/mvn.log" 2>&1; }

# Тесты варианта: печатает вывод Maven и отчёты Surefire; код выхода — как у Maven.
variant_test() {
    local dir=$1 code
    shift
    (cd "$dir" && timeout 900 mvn -B -ntp test "$@" 2>&1); code=$?
    cat "$dir"/target/surefire-reports/*.txt 2>/dev/null
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

# Последняя строка файла — закрывающая «}» класса: убрать её, чтобы дописать члены класса.
drop_last_brace() { sed -i '$d' "$1"; }

# Запущенные контейнеры Testcontainers: Postgres и уборщик Ryuk — «образ id».
tc_containers() { docker ps --format '{{.Image}} {{.ID}}' | grep -E "^($IMAGE|testcontainers/ryuk[^ ]*) "; }

wait_tc_gone() {
    local i
    for ((i = 0; i < 60; i++)); do
        [ -z "$(tc_containers)" ] && return 0
        sleep 1
    done
    return 1
}

# Покрытие Incident по отчёту JaCoCo: «веток пропущено, пройдено; строк пропущено, пройдено;
# вызван ли конструктор без аргументов (1/0)».
incident_coverage() {
    python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
for cls in ET.parse(sys.argv[1]).getroot().iter("class"):
    if cls.get("name") != "example/gameday/journal/Incident":
        continue
    c = {x.get("type"): (x.get("missed"), x.get("covered")) for x in cls.findall("counter")}
    init = "0"
    for m in cls.findall("method"):
        if m.get("name") == "<init>" and m.get("desc") == "()V":
            init = {x.get("type"): x.get("covered") for x in m.findall("counter")}.get("METHOD", "0")
    print(*c.get("BRANCH", ("?", "?")), *c.get("LINE", ("?", "?")), init)
PY
}

trap db_down EXIT

section "Сборка: стартер JPA вместо JDBC, тесты статьи на месте"
if grep -q '<artifactId>spring-boot-starter-jdbc</artifactId>' pom.xml; then
    fail "в pom.xml остался spring-boot-starter-jdbc"
else
    pass "spring-boot-starter-jdbc из pom.xml убран"
fi
expect_contains "$(cat pom.xml)" "<artifactId>spring-boot-starter-data-jpa</artifactId>" "в pom.xml — spring-boot-starter-data-jpa"
tree=$(mvn -B -ntp dependency:tree -Dincludes=org.springframework.boot:spring-boot-starter-jdbc 2>&1)
expect_contains "$tree" "org.springframework.boot:spring-boot-starter-jdbc:jar" "стартер JDBC в зависимостях есть"
expect_contains "$tree" "org.springframework.boot:spring-boot-starter-data-jpa:jar" \
    "его приносит стартер JPA — объявлять второй раз незачем"
note "$(grep -E 'spring-boot-starter-(data-jpa|jdbc):jar' <<<"$tree" | sed 's/^\[INFO\] //' | tr '\n' ' ')"
tree=$(mvn -B -ntp dependency:tree -Dincludes=jakarta.transaction:jakarta.transaction-api 2>&1)
expect_contains "$tree" "jakarta.transaction:jakarta.transaction-api:jar" \
    "jakarta.transaction.Transactional в зависимостях есть — поэтому IDE и предлагает два импорта"
expect_contains "$tree" "org.springframework.boot:spring-boot-starter-data-jpa:jar" "его приносит стартер JPA"
list=$(mvn -B -ntp dependency:list 2>&1)
expect_not_contains "$list" "spring-boot-data-jpa-test" "@DataJpaTest в песочнице нет: его модуля в зависимостях нет"
note "версии: $(grep -o -E '(org\.hibernate\.orm:hibernate-core|org\.springframework\.data:spring-data-jpa|jakarta\.transaction:jakarta\.transaction-api):jar:[^:]+' <<<"$list" | sort -u | tr '\n' ' ')"
expect_contains "$(cat src/main/resources/application.yml)" "ddl-auto: validate" "в application.yml — ddl-auto: validate"

suite_ok . example.gameday.journal.IncidentTest 10
suite_ok . example.gameday.journal.IncidentRepositoryIT 3
suite_ok . example.gameday.journal.IncidentLogIT 2
suite_ok . example.gameday.journal.IncidentTableIT 2
suite_ok . example.gameday.GameDayApplicationTests 1
if [ -e target/surefire-reports/TEST-example.gameday.journal.IncidentLogTest.xml ] \
    || [ -e "$TEST/IncidentLogTest.java" ] || [ -e "$TEST/RememberingNotifier.java" ]; then
    fail "IncidentLogTest или RememberingNotifier остались в песочнице"
else
    pass "IncidentLogTest и RememberingNotifier удалены"
fi
# Шесть строк таблицы прошли: «null» стал null, а строка — Instant (иначе первая и четвёртая упали бы).
note "строки таблицы в отчёте: $(grep -o -E 'testcase name="[^"]*ошибка"' \
    target/surefire-reports/TEST-example.gameday.journal.IncidentTest.xml 2>/dev/null \
    | sed -e 's/^testcase name=//' -e 's/&quot;/"/g' | tr '\n' ' ')"

section "Запуск: журнал пишет в базу, строки переживают перезапуск"
if db_up; then
    pass "docker run $IMAGE: база принимает подключения на 127.0.0.1:$PORT"
else
    fail "база в контейнере не поднялась"
fi
out=$(app); code=$?
expect_ok "$code" "java -jar с SPRING_DATASOURCE_* — сверка схемы (validate) прошла: Instant ↔ TIMESTAMPTZ, UUID"
[ "$code" -eq 0 ] || show "$(tail -n 40 <<<"$out")"
expect_contains "$out" 'Successfully applied 1 migration to schema "game_day"' "Flyway применил V1 к чистой базе"
expect_contains "$out" "[оповещение] duty-1: Брокер не отвечает — замечено " "оповещение — как в статье"
expect_contains "$out" "игра PT3H, атакующих 2" "настройки из статьи 2 на месте"
show "$(grep -E '\[оповещение\]|игра PT' <<<"$out")"
out=$(app); code=$?
expect_ok "$code" "второй запуск"
out=$(echo "SELECT title, duty_name, fixed_at FROM game_day.incident;" | psql_in)
expect_contains "$out" "       title        | duty_name | fixed_at" "шапка таблицы — как в статье"
expect_contains "$out" "--------------------+-----------+----------" "черта под шапкой — как в статье"
expect_contains "$out" " Брокер не отвечает | duty-1    |" "строка журнала: заголовок и дежурный, fixed_at пуст"
expect_contains "$out" "(2 rows)" "два запуска — две строки"
show "$out"

section "Сверка схемы: @Column(name = \"fixed\") — приложение не стартует"
v=$(make_variant column-typo)
sed -i 's/@Column(name = "fixed_at")/@Column(name = "fixed")/' "$v/$MAIN/Incident.java"
expect_contains "$(cat "$v/$MAIN/Incident.java")" '@Column(name = "fixed")' "в варианте столбец назван fixed"
if variant_jar "$v"; then
    out=$(app "$v/$JAR"); code=$?
    expect_failed "$code" "java -jar с опечаткой в имени столбца"
    expect_contains "$out" "Schema-validation: missing column [fixed] in table [game_day.incident]" \
        "текст ошибки — как в статье"
    show "$(grep -m 1 -o 'Schema-validation: missing column [^]]*] in table [^]]*]' <<<"$out")"
else
    fail "вариант column-typo не собрался"
    show "$(tail -n 30 "$v/mvn.log")"
fi

section "Метод по имени с опечаткой findByDuty_name — приложение не стартует"
v=$(make_variant duty-underscore)
sed -i 's/^\(    List<Incident> findByDutyName(String dutyName);\)$/\1\n\n    List<Incident> findByDuty_name(String dutyName);/' \
    "$v/$MAIN/IncidentRepository.java"
expect_contains "$(cat "$v/$MAIN/IncidentRepository.java")" "findByDuty_name(String dutyName);" \
    "в хранилище варианта — findByDuty_name"
if variant_jar "$v"; then
    out=$(app "$v/$JAR"); code=$?
    expect_failed "$code" "java -jar с findByDuty_name"
    expect_contains "$out" "No property 'duty' found for type 'Incident'" "текст ошибки — как в статье"
    show "$(grep -m 1 -o "No property 'duty' found for type 'Incident'[^;]*" <<<"$out")"
else
    fail "вариант duty-underscore не собрался"
    show "$(tail -n 30 "$v/mvn.log")"
fi

section "Старый журнал рядом с новым — два бина incidentLog, приложение не стартует"
v=$(make_variant two-journals)
if [ -f "$BASE/$MAIN/IncidentLog.java" ]; then
    mkdir -p "$v/src/main/java/example/gameday/legacy"
    sed -e 's/^package example\.gameday\.journal;$/package example.gameday.legacy;\n\nimport example.gameday.journal.DutyRoster;\nimport example.gameday.journal.Notifier;/' \
        "$BASE/$MAIN/IncidentLog.java" >"$v/src/main/java/example/gameday/legacy/IncidentLog.java"
    expect_contains "$(cat "$v/src/main/java/example/gameday/legacy/IncidentLog.java")" "@Component" \
        "старый журнал статьи 1 — в пакете example.gameday.legacy"
    if variant_jar "$v"; then
        out=$(app "$v/$JAR"); code=$?
        expect_failed "$code" "java -jar с двумя журналами"
        expect_contains "$out" "ConflictingBeanDefinitionException" "исключение — как в статье"
        expect_contains "$out" "Annotation-specified bean name 'incidentLog'" "имя бина — incidentLog"
        expect_contains "$out" "conflicts with existing, non-compatible bean definition" "текст ошибки — как в статье"
        show "$(grep -m 1 -o "Annotation-specified bean name 'incidentLog'.*" <<<"$out")"
    else
        fail "вариант two-journals не собрался"
        show "$(tail -n 30 "$v/mvn.log")"
    fi
else
    fail "нет $BASE/$MAIN/IncidentLog.java — пример статьи 3а не разложен"
fi
db_down

section "IncidentLogTest статьи 1 с новым конструктором не компилируется"
v=$(make_variant old-test)
if [ -f "$BASE/$TEST/IncidentLogTest.java" ] && [ -f "$BASE/$TEST/RememberingNotifier.java" ]; then
    cp "$BASE/$TEST/IncidentLogTest.java" "$BASE/$TEST/RememberingNotifier.java" "$v/$TEST/"
    out=$(cd "$v" && mvn -B -ntp test-compile 2>&1); code=$?
    expect_failed "$code" "mvn test-compile с IncidentLogTest статьи 1"
    expect_contains "$out" "cannot be applied to given types" "текст компилятора — как в статье"
    expect_contains "$out" "IncidentLogTest.java" "ошибка — в IncidentLogTest"
    show "$(grep -m 1 -A 3 'cannot be applied to given types' <<<"$out" | sed -E 's#/[^ ]*/(src/)#\1#')"
else
    fail "нет IncidentLogTest или RememberingNotifier в $BASE — пример статьи 3а не разложен"
fi

section "🔑 Без @Transactional на fixAll IncidentLogIT краснеет"
v=$(make_variant no-transactional)
sed -i '/^    @Transactional$/d' "$v/$MAIN/IncidentLog.java"
expect_not_contains "$(cat "$v/$MAIN/IncidentLog.java")" "@Transactional" "в варианте @Transactional с fixAll убран"
out=$(variant_test "$v" -Dtest=IncidentLogIT); code=$?
expect_failed "$code" "IncidentLogIT без @Transactional на fixAll"
expect_contains "$out" "Expected size: 3 but was: 0" "три закрытия остались в базе — сообщение как в статье"
expect_contains "$out" "fixAllRollsBackWhenOneIdIsUnknown" "упал тест отката"
expect_regex "$out" "Tests run: 2, Failures: 1, Errors: 0" "addStoresIncident зелёный — упал только откат"
show "$(grep -m 1 -A 1 'Expected size: 3 but was: 0' <<<"$out")"

section "⚠️ Тест в своей транзакции: @Transactional на IncidentLogIT — красный и с исправным fixAll"
v=$(make_variant transactional-test)
sed -i 's/^class IncidentLogIT {$/@org.springframework.transaction.annotation.Transactional\nclass IncidentLogIT {/' \
    "$v/$TEST/IncidentLogIT.java"
expect_contains "$(cat "$v/$TEST/IncidentLogIT.java")" "@org.springframework.transaction.annotation.Transactional" \
    "в варианте IncidentLogIT помечен @Transactional"
out=$(variant_test "$v" -Dtest=IncidentLogIT); code=$?
expect_failed "$code" "IncidentLogIT в своей транзакции"
expect_contains "$out" "Expected size: 3 but was: 0" "проверка видит закрытия, которые ещё не откатились"
expect_regex "$out" "Tests run: 2, Failures: 1, Errors: 0" "упал только тест отката"
show "$(grep -m 1 -A 1 'Expected size: 3 but was: 0' <<<"$out")"

section "jakarta.transaction.Transactional вместо Spring-ового — Spring понимает и его"
v=$(make_variant jakarta-transactional)
sed -i 's/^import org\.springframework\.transaction\.annotation\.Transactional;$/import jakarta.transaction.Transactional;/' \
    "$v/$MAIN/IncidentLog.java"
expect_contains "$(cat "$v/$MAIN/IncidentLog.java")" "import jakarta.transaction.Transactional;" \
    "в варианте — импорт jakarta.transaction.Transactional"
out=$(variant_test "$v" -Dtest=IncidentLogIT); code=$?
expect_ok "$code" "IncidentLogIT с jakarta.transaction.Transactional — откат тот же"
[ "$code" -eq 0 ] || show "$(grep -E 'Tests run:|FAIL|ERROR' <<<"$out" | head -n 20)"

section "Второй бин Clock с именем clock — приложение не стартует"
v=$(make_variant second-clock)
f="$v/$TEST/IncidentLogIT.java"
sed -i 's/^@Import(TestcontainersConfiguration\.class)$/@Import({TestcontainersConfiguration.class, IncidentLogIT.FixedClock.class})/' "$f"
drop_last_brace "$f"
cat >>"$f" <<'EOF'

    // Вариант для проверки: метод clock() с остановленными часами — в классе настроек теста.
    @org.springframework.boot.test.context.TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {

        @org.springframework.context.annotation.Bean
        java.time.Clock clock() {
            return java.time.Clock.fixed(T0, java.time.ZoneOffset.UTC);
        }
    }
}
EOF
expect_contains "$(cat "$f")" "IncidentLogIT.FixedClock.class" "в варианте — второй бин clock через @Import"
out=$(variant_test "$v" -Dtest=IncidentLogIT); code=$?
expect_failed "$code" "IncidentLogIT со вторым бином clock"
expect_contains "$out" "A bean with that name has already been defined" "Boot: бин с таким именем уже есть"
expect_contains "$out" "and overriding is disabled" "Boot: подменять бины нельзя — как в статье"
show "$(grep -m 1 -o "The bean 'clock'.*overriding is disabled\." <<<"$out")"

section "Второй бин Clock с другим именем — старт проходит, а журнал берёт бин clock"
v=$(make_variant other-clock)
f="$v/$TEST/IncidentLogIT.java"
sed -i 's/^@Import(TestcontainersConfiguration\.class)$/@Import({TestcontainersConfiguration.class, IncidentLogIT.FixedClock.class})/' "$f"
drop_last_brace "$f"
cat >>"$f" <<'EOF'

    @Test
    void journalKeepsItsOwnClock() {
        log.add("часы остановлены?");

        assertThat(incidents.findByDutyName("duty-1"))
                .extracting(Incident::getDetectedAt)
                .doesNotContain(T0);                             // остановленные часы показали бы T0
    }

    // Вариант для проверки: второй бин Clock с другим именем.
    @org.springframework.boot.test.context.TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {

        @org.springframework.context.annotation.Bean
        java.time.Clock fixedClock() {
            return java.time.Clock.fixed(T0, java.time.ZoneOffset.UTC);
        }
    }
}
EOF
expect_contains "$(cat "$f")" "java.time.Clock fixedClock()" "в варианте — второй бин fixedClock"
out=$(variant_test "$v" -Dtest=IncidentLogIT); code=$?
expect_ok "$code" "IncidentLogIT с бином fixedClock: старт прошёл, журнал не заметил подмены"
expect_regex "$out" "Tests run: 3, Failures: 0, Errors: 0" "все три теста, с journalKeepsItsOwnClock, зелёные"
[ "$code" -eq 0 ] || show "$(grep -E 'Tests run:|FAIL|ERROR|expected' <<<"$out" | head -n 20)"

section "Что статья говорит словами: наследник от Hibernate, микросекунды, прокси, проверяемое исключение, контекст"
# ArticleClaimsIT — тест только для прогона; два метода журнала — только в варианте.
v=$(make_variant claims)
drop_last_brace "$v/$MAIN/IncidentLog.java"
cat >>"$v/$MAIN/IncidentLog.java" <<'EOF'

    // Только для проверки прогона: fixAll изнутри того же класса — мимо прокси.
    public void fixAllFromInside(List<UUID> ids) {
        fixAll(ids);
    }

    // Только для проверки прогона: то же, что fixAll, но с проверяемым исключением.
    @Transactional
    public void fixAllChecked(List<UUID> ids) throws Exception {
        Instant now = clock.instant();
        for (UUID id : ids) {
            Incident incident = incidents.findById(id)
                    .orElseThrow(() -> new Exception("нет происшествия " + id));
            incident.fix(now);
            incidents.save(incident);
        }
    }
}
EOF
cat >"$v/$TEST/ArticleClaimsIT.java" <<'EOF'
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Проверки прогона к статье 3б: то, что статья говорит словами. В статью не идёт. */
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class ArticleClaimsIT {

    private static final Instant T0 = Instant.parse("2026-09-01T09:15:00Z");

    @Autowired
    private IncidentLog log;

    @Autowired
    private IncidentRepository incidents;

    @Autowired
    private EntityManager entityManager;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    private List<UUID> threeOpenAndOneUnknown() {
        List<UUID> ids = new ArrayList<>();
        for (String title : List.of("стенд не отвечает", "очередь растёт", "письма не уходят")) {
            ids.add(incidents.save(new Incident(title, T0, "duty-1")).getId());
        }
        ids.add(UUID.randomUUID());
        return ids;
    }

    @Test
    void hibernateSubstitutesSubclass() {
        UUID id = incidents.save(new Incident("стенд не отвечает", T0, "duty-1")).getId();

        Class<?> type = incidents.getReferenceById(id).getClass();

        System.out.println("CLAIM proxy: " + type.getName() + " extends " + type.getSuperclass().getName());
        assertThat(type).isNotEqualTo(Incident.class);
        assertThat(type.getSuperclass()).isEqualTo(Incident.class);
    }

    @Test
    void timestamptzKeepsMicroseconds() {
        Instant written = Instant.parse("2026-10-05T09:15:00.123456789Z");
        UUID id = incidents.save(new Incident("стенд не отвечает", written, "duty-1")).getId();

        Instant read = incidents.findById(id).orElseThrow().getDetectedAt();

        System.out.println("CLAIM time: written " + written + ", read " + read);
        assertThat(read).isNotEqualTo(written);
        assertThat(read.getNano() % 1000).isZero();
    }

    @Test
    void callFromInsideSkipsTransaction() {
        List<UUID> ids = threeOpenAndOneUnknown();

        assertThatThrownBy(() -> log.fixAllFromInside(ids)).isInstanceOf(IllegalArgumentException.class);

        assertThat(incidents.findByFixedAtIsNull()).isEmpty();
    }

    @Test
    void checkedExceptionCommits() {
        List<UUID> ids = threeOpenAndOneUnknown();

        assertThatThrownBy(() -> log.fixAllChecked(ids))
                .isInstanceOf(Exception.class)
                .isNotInstanceOf(RuntimeException.class);

        assertThat(incidents.findByFixedAtIsNull()).isEmpty();
    }

    @Test
    @Transactional
    void insideTestTransactionReadReturnsSameObject() {
        Incident saved = incidents.save(new Incident("стенд не отвечает", T0, "duty-1"));

        assertThat(incidents.findById(saved.getId())).containsSame(saved);

        entityManager.flush();
        entityManager.clear();
        assertThat(incidents.findById(saved.getId()).orElseThrow()).isNotSameAs(saved);
    }

    @Test
    void withoutTestTransactionReadGoesToDatabase() {
        Incident saved = incidents.save(new Incident("стенд не отвечает", T0, "duty-1"));

        assertThat(incidents.findById(saved.getId()).orElseThrow()).isNotSameAs(saved);
    }
}
EOF
# Заодно — «контейнер на прогон по-прежнему один»: следим за docker ps, пока идут все тесты на базе.
wait_tc_gone || note "контейнеры Testcontainers от прошлого прогона ещё живы"
(cd "$v" && timeout 900 mvn -B -ntp test -Dtest="$DB_TESTS,ArticleClaimsIT" >"$v/mvn.log" 2>&1) &
pid=$!
seen=""
while kill -0 "$pid" 2>/dev/null; do
    seen+="$(tc_containers)"$'\n'
    sleep 1
done
wait "$pid"; code=$?
out=$(cat "$v/mvn.log" "$v"/target/surefire-reports/*.txt 2>/dev/null)
expect_ok "$code" "тесты на базе и ArticleClaimsIT"
[ "$code" -eq 0 ] || show "$(grep -E 'Tests run:|FAIL|ERROR|expected|Expect' <<<"$out" | head -n 30)"
suite_ok "$v" example.gameday.journal.ArticleClaimsIT 6
expect_regex "$out" "CLAIM proxy: example\.gameday\.journal\.Incident\\\$[^ ]+ extends example\.gameday\.journal\.Incident" \
    "Hibernate подставляет наследника Incident — поэтому сущность не final"
note "$(grep -m 1 -o 'CLAIM proxy: .*' <<<"$out")"
note "$(grep -m 1 -o 'CLAIM time: .*' <<<"$out")"
postgres_count=$(grep -c "^$IMAGE " <<<"$(sort -u <<<"$seen")")
if [ "$postgres_count" -eq 1 ]; then
    pass "контейнер Postgres один на пять тестовых классов — приложение из кэша Spring"
else
    fail "контейнеров Postgres за прогон: $postgres_count, а статья обещает один"
fi

section "Покрытие: ветки Incident проходит IncidentTest, конструктор для JPA — тесты на базе"
v=$(make_variant jacoco)
report="$v/target/site/jacoco/jacoco.xml"
out=$(cd "$v" && mvn -B -ntp "$JACOCO:prepare-agent" test "$JACOCO:report" -Dtest=IncidentTest 2>&1); code=$?
expect_ok "$code" "IncidentTest под JaCoCo"
read -r bm bc lm lc init < <(incident_coverage "$report")
if [ "${bm:-?}" = "0" ] && [ "${bc:-0}" != "0" ]; then
    pass "IncidentTest: все ветки Incident ($bc) пройдены"
else
    fail "IncidentTest: ветки Incident — пропущено ${bm:-?}, пройдено ${bc:-?}"
fi
if [ "${init:-?}" = "0" ]; then
    pass "без базы protected Incident() не вызван (строк пропущено: ${lm:-?})"
else
    fail "без базы protected Incident() вызван — статья говорит обратное"
fi
rm -f "$v/target/jacoco.exec"
out=$(cd "$v" && mvn -B -ntp "$JACOCO:prepare-agent" test "$JACOCO:report" -Dtest='IncidentTest,IncidentRepositoryIT' 2>&1)
code=$?
expect_ok "$code" "IncidentTest и IncidentRepositoryIT под JaCoCo"
read -r bm bc lm lc init < <(incident_coverage "$report")
if [ "${init:-?}" = "1" ]; then
    pass "с тестом на базе protected Incident() вызван — его зовёт Hibernate"
else
    fail "protected Incident() не покрыт и тестами на базе"
fi
note "Incident с тестами на базе: веток пропущено ${bm:-?}, пройдено ${bc:-?}; строк пропущено ${lm:-?}, пройдено ${lc:-?}"

section "⚠️ @DataJpaTest в Boot 4 — свой стартер и пакет org.springframework.boot.data.jpa.test.autoconfigure"
v=$(make_variant data-jpa-test)
perl -0pi -e 's#(\n\s*</dependencies>)#\n        <dependency>\n            <groupId>org.springframework.boot</groupId>\n            <artifactId>spring-boot-starter-data-jpa-test</artifactId>\n            <scope>test</scope>\n        </dependency>$1#' \
    "$v/pom.xml"
expect_contains "$(cat "$v/pom.xml")" "<artifactId>spring-boot-starter-data-jpa-test</artifactId>" \
    "в pom.xml варианта — spring-boot-starter-data-jpa-test"
cat >"$v/$TEST/DataJpaTestPackage.java" <<'EOF'
package example.gameday.journal;

import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;

/** Только для проверки прогона: где @DataJpaTest в Boot 4. Тестов нет — Surefire его не запускает. */
@DataJpaTest
class DataJpaTestPackage {
}
EOF
out=$(cd "$v" && mvn -B -ntp test-compile 2>&1); code=$?
expect_ok "$code" "@DataJpaTest из org.springframework.boot.data.jpa.test.autoconfigure компилируется"
[ "$code" -eq 0 ] || show "$(grep -E 'ERROR' <<<"$out" | head -n 10)"

# Убрать базу статьи, если что-то оборвалось раньше; последняя команда — с кодом 0.
db_down
