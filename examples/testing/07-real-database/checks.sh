# Статья 7 «Тест с настоящей базой» серии «От красного к зелёному» — утверждения статьи, которые проверяет
# прогон. Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница testy — после статьи 6; pom.xml — как после статьи 5, плюс JDBC, Flyway, драйвер Postgres,
# Testcontainers и шаблоны Surefire. Код статьи — V1__score.sql, JdbcScoreBoard, TestcontainersConfiguration,
# TestyApplicationTests с @Import и JdbcScoreBoardIT. В mvn verify песочница уже прошла — на Postgres в контейнере.
# Здесь — то, что статья обещает словами: куски кода в тексте — строки «Пример целиком»; тексты ошибок Postgres
# и SQLSTATE на postgres:17-alpine; Tests run: 28, один контейнер и один контекст на прогон, после прогона
# контейнеров нет; второй зачёт — DuplicateKeyException с score_pkey, балл 70 — DataIntegrityViolationException
# с score_score_check; без CHECK, без PRIMARY KEY и с опечаткой в INSERT краснеют названные тесты; без уборки
# один тест красный при любом порядке, в Errors; уборка до спасает от чужой строки, уборка после — нет;
# @MockitoBean — второй контекст и второй контейнер; без **/*Tests.java — Tests run: 27; без @Import и без
# базы — Failed to configure a DataSource; без Docker — Could not find a valid Docker environment.

PKG=example.testy.score
IT=$PKG.JdbcScoreBoardIT
APP=example.testy.TestyApplicationTests
MIGRATION=src/main/resources/db/migration/V1__score.sql
BOARD=src/main/java/example/testy/score/JdbcScoreBoard.java
IT_FILE=src/test/java/example/testy/score/JdbcScoreBoardIT.java
APP_FILE=src/test/java/example/testy/TestyApplicationTests.java
TEST_DIR=src/test/java/example/testy/score
JAR=target/testy-0.0.1-SNAPSHOT.jar
ARTICLE=${ROOT:-}/testing/07-real-database.md
BASE_POM=${ROOT:-}/examples/testing/05-test-that-checks-nothing/pom.xml
IMAGE=postgres:17-alpine
DB=testy-score-db
T1=recordedScoreCanBeReadBack
T2=unknownTaskHasNoScore
T3=secondScoreForSameTaskIsRejected
T4=scoreOutsideRuleIsRejectedByDatabase
ALL4="$T1 $T2 $T3 $T4"
# shellcheck disable=SC2016  # $ — часть имени класса JUnit, а не переменная bash
BY_NAME='org.junit.jupiter.api.MethodOrderer$MethodName'
TEXT="$VARIANTS/$(basename "$PWD")-text"    # куски статьи — вне target: mvn их не сотрёт

# Строка вывода целиком, как в статье; пробелы в конце строки не в счёт. Аргументы: вывод, строка, пояснение.
expect_line() {
    if sed 's/[[:space:]]*$//' <<<"$1" | grep -xF -- "$2" >/dev/null; then pass "$3"; else fail "$3: нет строки «$2»"; fi
}

# Итог «Tests run: …» из раздела Results и строка BUILD — для сводки. Аргумент: вывод mvn.
summary_lines() { grep -E '^\[(INFO|ERROR)\] (Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+ *$|BUILD )' <<<"$1"; }

# Отчёт Surefire о классе: «тестов N, все зелёные». Аргументы: папка проекта, класс, N.
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

# Исход одного теста по отчёту Surefire: ok, absent или «error|failure <тип исключения>».
# Аргументы: папка проекта, класс, метод.
case_state() {
    local file="$1/target/surefire-reports/TEST-$2.xml"
    if [ ! -f "$file" ]; then echo absent; return; fi
    M=$3 perl -0ne '
        if (/<testcase\b[^>]*\bname="\Q$ENV{M}\E"[^>]*?(?:\/>|>(.*?)<\/testcase>)/s) {
            my $body = $1 // "";
            if ($body =~ /<(error|failure)\b(?:[^>"]|"[^"]*")*?\btype="([^"]*)"/s) { print "$1 $2\n" }
            elsif ($body =~ /<(error|failure)\b/) { print "$1\n" }
            else { print "ok\n" }
        } else { print "absent\n" }' "$file"
}

# Итог JdbcScoreBoardIT: красные — названные, остальные из четырёх — зелёные. Аргументы: папка, пояснение, красные…
expect_reds() {
    local dir=$1 what=$2 t state
    shift 2
    for t in $ALL4; do
        state=$(case_state "$dir" "$IT" "$t")
        if [[ " $* " == *" $t "* ]]; then
            if [[ "$state" == error* || "$state" == failure* ]]; then pass "$what: красный $t — $state"
            else fail "$what: $t не красный ($state)"; fi
        elif [ "$state" = "ok" ]; then
            pass "$what: зелёный $t"
        else
            fail "$what: $t не зелёный ($state)"
        fi
    done
}

# Правка варианта должна лечь. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    pass "в варианте: $3"
}

# mvn в папке варианта; вывод — в OUT, код — в CODE. Аргументы: папка, аргументы mvn.
OUT=""
CODE=0
mvn_in() {
    local dir=$1
    shift
    OUT=$(cd "$dir" && timeout 900 mvn -B -ntp "$@" 2>&1); CODE=$?
}

# Запущенные контейнеры Testcontainers: Postgres статьи и уборщик Ryuk — «образ id».
tc_containers() { docker ps --format '{{.Image}} {{.ID}}' | grep -E "^($IMAGE|testcontainers/ryuk[^ ]*) "; }

wait_tc_gone() {
    local i
    for ((i = 0; i < 60; i++)); do
        [ -z "$(tc_containers)" ] && return 0
        sleep 1
    done
    return 1
}

# mvn в фоне, а рядом раз в секунду docker ps; увиденное — в SEEN. Аргументы: папка, аргументы mvn.
SEEN=""
mvn_watching_docker() {
    local dir=$1 pid
    shift
    SEEN=""
    (cd "$dir" && timeout 900 mvn -B -ntp "$@" >"$dir/mvn.log" 2>&1) &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        SEEN+="$(tc_containers)"$'\n'
        sleep 1
    done
    wait "$pid"; CODE=$?
    OUT=$(cat "$dir/mvn.log")
}

postgres_count() { grep "^$IMAGE " <<<"$SEEN" | cut -d ' ' -f 2 | sort -u | grep -c .; }
contexts_started() { grep -cE 'Started [A-Za-z0-9_]+ in [0-9.]+ seconds' <<<"$OUT"; }

# Пробы для вариантов — в статью не идут: сосед, который оставляет зачёт «student-1 — T-7»;
# порядок тестов в классе — по имени или в обратном; порядок классов — по имени.
add_leftover() {
    cat >"$1/$TEST_DIR/AaaLeftoverIT.java" <<'EOF'
package example.testy.score;

import example.testy.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

// Проба checks.sh статьи 7: сосед, который пишет зачёт и не убирает за собой.
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class AaaLeftoverIT {

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    void leavesScoreBehind() {
        jdbc.update("INSERT INTO score (student_id, task_key, score) VALUES ('student-1', 'T-7', 100)");
    }
}
EOF
}

add_reverse_order() {
    cat >"$1/$TEST_DIR/ReverseMethodName.java" <<'EOF'
package example.testy.score;

import org.junit.jupiter.api.MethodDescriptor;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.MethodOrdererContext;

import java.util.Comparator;

// Проба checks.sh статьи 7: тесты класса — в обратном порядке имён.
public class ReverseMethodName implements MethodOrderer {

    @Override
    public void orderMethods(MethodOrdererContext context) {
        context.getMethodDescriptors().sort(
                Comparator.comparing((MethodDescriptor m) -> m.getMethod().getName()).reversed());
    }
}
EOF
}

# Порядок для JUnit: классы по имени, тесты в классе — так, как велит первый аргумент. Аргументы: папка, орудие.
set_order() {
    mkdir -p "$1/src/test/resources"
    # shellcheck disable=SC2016  # $ — часть имени класса JUnit, а не переменная bash
    printf '%s\n' 'junit.jupiter.testclass.order.default=org.junit.jupiter.api.ClassOrderer$ClassName' \
        "junit.jupiter.testmethod.order.default=$2" >"$1/src/test/resources/junit-platform.properties"
}

db_down() { docker rm -f "$DB" >/dev/null 2>&1; return 0; }
trap db_down EXIT

section "Код статьи: куски в тексте — строки «Пример целиком»; pom.xml — как после статьи 5 плюс кусок статьи"
for f in "$MIGRATION" "$BOARD" "$IT_FILE" "$APP_FILE" src/test/java/example/testy/TestcontainersConfiguration.java; do
    expect_file "$f"
done
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    rm -rf "$TEXT" && mkdir -p "$TEXT"
    awk -v dir="$TEXT" '/^## Пример целиком/ { full = 1 }
        /^```(java|sql|xml)$/ { inside = 1; n++; name = (full ? "full-" : "part-") n; next }
        inside && /^```$/ { inside = 0; next }
        inside { print > (dir "/" name ".txt") }' "$ARTICLE"
    cat "$TEXT"/full-*.txt | sed 's/^[[:space:]]*//' | grep -v '^$' | sort -u >"$TEXT/known.txt"
    k=0
    for part in "$TEXT"/part-*.txt; do
        [ -f "$part" ] || continue
        k=$((k + 1))
        missing=$(sed 's/^[[:space:]]*//' "$part" | grep -v '^$' | grep -vxF -f "$TEXT/known.txt")
        if [ -z "$missing" ]; then pass "кусок $(basename "$part" .txt) — строки «Пример целиком»"
        else fail "кусок $(basename "$part" .txt): этих строк нет в «Пример целиком»"; show "$missing"; fi
    done
    if [ "$k" -eq 6 ]; then pass "кусков кода в тексте 6"; else fail "кусков кода в тексте $k, ждали 6"; fi
    artifacts() { sed -nE 's#^[[:space:]]*<artifactId>([^<]+)</artifactId>.*#\1#p' | sort; }
    fragment=$(awk '/^## Пример целиком/ { full = 1 } full && /^```xml$/ { inside = 1; next }
        inside && /^```$/ { exit } inside' "$ARTICLE")
    want=$( { artifacts <"$BASE_POM"; artifacts <<<"$fragment"; } | sort)
    if [ -f "$BASE_POM" ] && [ "$want" = "$(artifacts <pom.xml)" ]; then
        pass "pom.xml — как после статьи 5, плюс ровно то, что добавляет кусок статьи"
    else
        fail "pom.xml расходится с «статья 5 + кусок статьи 7»"
        show "$(diff <(echo "$want") <(artifacts <pom.xml))"
    fi
    if [ "$(grep -o '<include>[^<]*</include>' pom.xml)" = "$(grep -o '<include>[^<]*</include>' <<<"$fragment")" ]; then
        pass "шаблоны Surefire в pom.xml — как в статье: *Test, *Tests, *IT"
    else
        fail "шаблоны Surefire в pom.xml расходятся со статьёй"
    fi
fi

section "Что отвечает база: тексты ошибок и SQLSTATE на $IMAGE"
db_down
docker run -d --rm --name "$DB" -e POSTGRES_PASSWORD=testy-local "$IMAGE" >/dev/null
ready=1
for _ in $(seq 90); do
    docker exec "$DB" pg_isready -q -h 127.0.0.1 -U postgres && { ready=0; break; }
    sleep 1
done
if [ "$ready" -eq 0 ]; then pass "docker run $IMAGE: база принимает подключения"; else fail "база в контейнере не поднялась"; fi
out=$( { cat "$MIGRATION"; cat <<'EOF'
INSERT INTO score (student_id, task_key, score) VALUES ('student-1', 'T-7', 100);
INSERT INTO score (student_id, task_key, score) VALUES ('student-1', 'T-7', 50);
INSERT INTO score (student_id, task_key, score) VALUES ('student-1', 'T-8', 70);
\set VERBOSITY verbose
INSERT INTO score (student_id, task_key, score) VALUES ('student-1', 'T-7', 50);
INSERT INTO score (student_id, task_key, score) VALUES ('student-1', 'T-8', 70);
EOF
} | docker exec -i "$DB" psql -X -U postgres 2>&1)
expect_contains "$out" 'ERROR:  duplicate key value violates unique constraint "score_pkey"' "второй зачёт — строка ошибки, как в статье"
expect_contains "$out" 'ERROR:  new row for relation "score" violates check constraint "score_score_check"' "балл 70 — строка ошибки, как в статье"
expect_contains "$out" 'ERROR:  23505: duplicate key value' "SQLSTATE повтора ключа — 23505"
expect_contains "$out" 'ERROR:  23514: new row for relation "score"' "SQLSTATE нарушенной проверки — 23514"
show "$(grep '^ERROR:' <<<"$out")"
db_down

section "./mvnw verify: Tests run: 28; один контейнер и один контекст на прогон; после прогона контейнеров нет"
wait_tc_gone || note "контейнеры Testcontainers от прошлого прогона ещё живы"
V=$(make_variant as-is)
mvn_watching_docker "$V" verify
expect_ok "$CODE" "mvn verify"
expect_line "$OUT" "[INFO] Tests run: 28, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 28 — 24 после статьи 6 и четыре новых"
show "$(summary_lines "$OUT")"
suite_ok "$V" "$IT" 4
suite_ok "$V" "$APP" 1
if [ "$(postgres_count)" = "1" ]; then pass "контейнер $IMAGE за прогон один на оба класса"
else fail "контейнеров $IMAGE за прогон: $(postgres_count), а статья обещает один"; fi
expect_regex "$SEEN" "^testcontainers/ryuk" "рядом в docker ps — Ryuk"
show "$(sort -u <<<"$SEEN" | sed '/^$/d')"
if [ "$(contexts_started)" = "1" ]; then pass "контекст Spring поднят один раз"
else fail "контекст поднимали $(contexts_started) раз(а), ждали один"; fi
if wait_tc_gone; then pass "после прогона ни Postgres, ни Ryuk не осталось"; else fail "после прогона остались: $(tc_containers | tr '\n' ' ')"; fi

section "Второй зачёт — DuplicateKeyException с score_pkey, балл 70 — DataIntegrityViolationException с score_score_check"
mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp-test.txt -Dmdep.includeScope=test >/dev/null
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE"
cat >"$PROBE/Hierarchy.java" <<'EOF'
// Проба checks.sh статьи 7: от кого наследуют исключения Spring для ошибок базы.
class Hierarchy {
    public static void main(String[] args) throws Exception {
        for (String name : args) {
            StringBuilder chain = new StringBuilder(name);
            for (Class<?> c = Class.forName(name).getSuperclass(); c != null; c = c.getSuperclass()) {
                chain.append(" < ").append(c.getName());
            }
            System.out.println(chain);
        }
    }
}
EOF
chain=$(java "${UTF8[@]}" -cp "$(cat target/cp-test.txt)" "$PROBE/Hierarchy.java" \
    org.springframework.dao.DuplicateKeyException 2>&1)
expect_contains "$chain" "DuplicateKeyException < org.springframework.dao.DataIntegrityViolationException" \
    "DuplicateKeyException — наследник DataIntegrityViolationException"
expect_contains "$chain" "< java.lang.RuntimeException" "…и оба непроверяемые"
show "$chain"
V=$(make_variant strict)
perl -0pi -e 's/\.isInstanceOf\(DuplicateKeyException\.class\);/.isExactlyInstanceOf(DuplicateKeyException.class)\n                .hasMessageContaining("score_pkey");/; s/\.isInstanceOf\(DataIntegrityViolationException\.class\);/.isExactlyInstanceOf(DataIntegrityViolationException.class)\n                .hasMessageContaining("score_score_check");/' "$V/$IT_FILE"
if [ "$(grep -c 'hasMessageContaining' "$V/$IT_FILE")" = "2" ]; then pass "в варианте: точный тип и имя ограничения в обеих проверках"
else fail "вариант strict: правка проверок не легла"; fi
add_leftover "$V"
set_order "$V" "$BY_NAME"
mvn_in "$V" test -Dtest='AaaLeftoverIT,JdbcScoreBoardIT' -Dsurefire.runOrder=alphabetical
expect_ok "$CODE" "строгие проверки и чужая строка перед классом: mvn test"
suite_ok "$V" "$PKG.AaaLeftoverIT" 1
suite_ok "$V" "$IT" 4
if [ "$(grep -n 'Running example.testy.score.AaaLeftoverIT' <<<"$OUT" | cut -d: -f1)" \
    -lt "$(grep -n "Running $IT" <<<"$OUT" | cut -d: -f1)" ] 2>/dev/null; then
    pass "сосед с чужой строкой шёл первым — уборка до теста её убрала"
else
    fail "сосед не шёл перед JdbcScoreBoardIT"
fi

section "Сначала — красный: без CHECK, без PRIMARY KEY, с опечаткой в INSERT"
V=$(make_variant no-check)
perl -pi -e 's/ CHECK \(score IN \(0, 50, 100\)\)//' "$V/$MIGRATION"
if expect_changed "$V/$MIGRATION" "$MIGRATION" "из V1__score.sql убран CHECK (score IN (0, 50, 100))"; then
    mvn_in "$V" test -Dtest=JdbcScoreBoardIT
    expect_reds "$V" "без CHECK" "$T4"
fi
V=$(make_variant no-key)
perl -0pi -e 's/\),(\s*-- других баллов[^\n]*)\n    PRIMARY KEY \(student_id, task_key\)[^\n]*\n/)$1\n/' "$V/$MIGRATION"
if expect_changed "$V/$MIGRATION" "$MIGRATION" "убраны строка PRIMARY KEY и запятая после CHECK (…)"; then
    mvn_in "$V" test -Dtest=JdbcScoreBoardIT
    expect_reds "$V" "без PRIMARY KEY" "$T3"
fi
V=$(make_variant typo)
perl -pi -e 's/\(student_id, task_key, score\) VALUES/(student_id, task_key, scor) VALUES/' "$V/$BOARD"
if expect_changed "$V/$BOARD" "$BOARD" "в INSERT столбец score → scor"; then
    mvn_in "$V" test -Dtest=JdbcScoreBoardIT
    expect_reds "$V" "опечатка в INSERT" "$T1" "$T3" "$T4"
    expect_contains "$OUT$(cat "$V"/target/surefire-reports/*.txt 2>/dev/null)" 'column "scor" of relation "score" does not exist' \
        "база назвала опечатку на первом же запросе"
fi

section "Без уборки один из двух тестов красный при любом порядке — и в Errors"
for order in name reverse; do
    V=$(make_variant "no-cleanup-$order")
    perl -0pi -e 's/\n    \@BeforeEach\n    void emptyTable\(\) \{\n[^\n]*\n    \}\n//' "$V/$IT_FILE"
    expect_changed "$V/$IT_FILE" "$IT_FILE" "удалён метод emptyTable с @BeforeEach ($order)" || continue
    if [ "$order" = name ]; then
        set_order "$V" "$BY_NAME"
        red=$T3
    else
        add_reverse_order "$V"
        set_order "$V" 'example.testy.score.ReverseMethodName'
        red=$T1
    fi
    mvn_in "$V" test -Dtest=JdbcScoreBoardIT
    expect_reds "$V" "без уборки, порядок $order" "$red"
    expect_regex "$(case_state "$V" "$IT" "$red")" '^error .*DuplicateKeyException' \
        "$red — Errors: упал на первой же записи, до проверки"
done

section "Уборка после не спасает от чужой строки: первый тест класса падает"
V=$(make_variant after-each)
perl -pi -e 's/BeforeEach/AfterEach/g' "$V/$IT_FILE"
if expect_changed "$V/$IT_FILE" "$IT_FILE" "@BeforeEach → @AfterEach"; then
    add_leftover "$V"
    set_order "$V" "$BY_NAME"
    mvn_in "$V" test -Dtest='AaaLeftoverIT,JdbcScoreBoardIT' -Dsurefire.runOrder=alphabetical
    expect_reds "$V" "уборка после, чужая строка" "$T1"
fi

section "Своя заглушка @MockitoBean — второй контекст и второй контейнер"
wait_tc_gone || note "контейнеры Testcontainers от прошлого прогона ещё живы"
V=$(make_variant mockito-bean)
# shellcheck disable=SC2016  # $1 — группа perl, а не переменная bash
perl -0pi -e 's/^(class TestyApplicationTests \{\n)/$1\n    \@MockitoBean\n    private Deadlines deadlines;\n/m; s/^(import org\.junit\.jupiter\.api\.Test;)$/import example.testy.score.Deadlines;\n$1/m; s/^(import org\.springframework\.context\.annotation\.Import;)$/$1\nimport org.springframework.test.context.bean.override.mockito.MockitoBean;/m' "$V/$APP_FILE"
if expect_changed "$V/$APP_FILE" "$APP_FILE" "в TestyApplicationTests — поле @MockitoBean"; then
    mvn_watching_docker "$V" test -Dtest='TestyApplicationTests,JdbcScoreBoardIT'
    expect_ok "$CODE" "mvn test с @MockitoBean"
    suite_ok "$V" "$APP" 1
    suite_ok "$V" "$IT" 4
    if [ "$(postgres_count)" = "2" ]; then pass "контейнеров $IMAGE за прогон два"
    else fail "контейнеров $IMAGE за прогон: $(postgres_count), ждали два"; fi
    if [ "$(contexts_started)" = "2" ]; then pass "контекстов Spring два"
    else fail "контекстов поднято $(contexts_started), ждали два"; fi
fi

section "Без **/*Tests.java — сборка зелёная, но Tests run: 27"
V=$(make_variant no-tests-pattern)
perl -ni -e 'print unless m#<include>\*\*/\*Tests\.java</include>#' "$V/pom.xml"
if expect_changed "$V/pom.xml" pom.xml "из шаблонов убран **/*Tests.java"; then
    mvn_in "$V" test
    expect_ok "$CODE" "mvn test без **/*Tests.java"
    expect_line "$OUT" "[INFO] Tests run: 27, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 27"
    if [ ! -f "$V/target/surefire-reports/TEST-$APP.xml" ]; then pass "TestyApplicationTests пропал из отчёта — молча"
    else fail "TestyApplicationTests всё ещё в отчёте"; fi
    show "$(summary_lines "$OUT")"
fi

section "Без @Import и без базы — Failed to configure a DataSource"
V=$(make_variant no-import)
sed -i -e '/^@Import(TestcontainersConfiguration.class)/d' -e '/^import org.springframework.context.annotation.Import;/d' \
    "$V/$APP_FILE"
if expect_changed "$V/$APP_FILE" "$APP_FILE" "из TestyApplicationTests убран @Import"; then
    mvn_in "$V" test -Dtest=TestyApplicationTests
    expect_failed "$CODE" "тест от Initializr без @Import"
    expect_contains "$OUT$(cat "$V"/target/surefire-reports/*.txt 2>/dev/null)" "Failed to configure a DataSource" \
        "текст ошибки — как в статье"
fi
out=$(timeout 180 java "${UTF8[@]}" -jar "$JAR" 2>&1); code=$?
expect_failed "$code" "TestyApplication без базы: java -jar"
expect_contains "$out" "Failed to configure a DataSource" "…с той же ошибкой"
show "$(grep -m 1 'Failed to configure a DataSource' <<<"$out")"

section "Docker не запущен — красные пять тестов со Spring, Could not find a valid Docker environment"
# Docker на машине CI не остановить, не сломав соседей. Поэтому прогон идёт там, где Docker нет:
# в контейнере с JDK, без сокета Docker; Maven и локальный репозиторий — с машины, без сети.
mvn_home=$(mvn -v 2>/dev/null | sed -n 's/^Maven home: //p')
repo="$HOME/.m2/repository"
if [ -z "$mvn_home" ] || [ ! -d "$repo" ]; then
    fail "не нашёл Maven ($mvn_home) или локальный репозиторий ($repo)"
else
    V=$(make_variant no-docker)
    out=$(timeout 900 docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$mvn_home":/opt/maven:ro -v "$repo":/m2 -v "$V":/work -w /work \
        eclipse-temurin:25-jdk-alpine \
        /opt/maven/bin/mvn -B -o -ntp -Dmaven.repo.local=/m2 test 2>&1); code=$?
    expect_failed "$code" "mvn test без Docker"
    expect_contains "$out$(cat "$V"/target/surefire-reports/*.txt 2>/dev/null)" \
        "Could not find a valid Docker environment" "текст ошибки Testcontainers — как в статье"
    expect_reds "$V" "без Docker" "$T1" "$T2" "$T3" "$T4"
    expect_regex "$(case_state "$V" "$APP" contextLoads)" '^error' "TestyApplicationTests красный, хотя таблиц не трогает"
    suite_ok "$V" "$PKG.DeadlineScoreTest" 12
    suite_ok "$V" "$PKG.AttemptsTest" 5
    suite_ok "$V" "$PKG.ScoreServiceTest" 3
    suite_ok "$V" "$PKG.ScoreServiceMockitoTest" 3
    show "$(summary_lines "$out")"
fi

section "Ссылки статьи открываются"
for link in https://docs.spring.io/spring-boot/reference/testing/testcontainers.html \
    https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html \
    https://docs.spring.io/spring/reference/data-access/dao.html \
    https://documentation.red-gate.com/fd/versioned-migrations-273973333.html \
    https://java.testcontainers.org/supported_docker_environment/ \
    https://hammerhall.io/ledger/testing/6-stubs \
    https://hammerhall.io/ledger/articles/3a-table-and-migration \
    https://hammerhall.io/ledger/articles/3b-entity-and-transaction \
    https://hammerhall.io/ledger/articles/6-stand; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done

# Убрать базу статьи, если что-то оборвалось раньше; последняя команда — с кодом 0.
db_down
