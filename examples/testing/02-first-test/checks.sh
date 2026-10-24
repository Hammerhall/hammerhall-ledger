# Статья 2 «Первый модульный тест: от пустого файла до зелёного отчёта» серии «От красного к зелёному» —
# утверждения статьи, которые проверяет прогон. Запускает tools/run_examples.sh из папки собранного примера;
# функции — tools/checks_lib.sh.
#
# Песочница testy — после статьи 1: DeadlineScore и ManualCheck оттуда, DeadlineScoreTest статьи 2 (четыре
# теста, константа DEADLINE, @DisplayName на одном) заменил однотестовый. В mvn verify он уже прошёл. Здесь —
# то, что статья обещает словами: класс без public, ожидания — числа; итог Maven — «Tests run: 5», строка
# Running и итог класса «Tests run: 4», имён тестов в зелёном журнале нет; -Dtest — класс и один тест;
# каждый тест хоть раз красный на своей поломке (таблица части 4 и isBefore из статьи 1), сутки в 23 часа
# не видит никто; FULL = 10 роняет тесты с числом, а тест с DeadlineScore.FULL зелёный; import org.junit.Test
# и assertThat из Hamcrest не компилируются; русское имя Maven по умолчанию не показывает, а с настройкой
# Surefire оно в отчёте; JUnit 4 без Vintage сборка не запускает («скорее всего» — смотрим); ссылки открываются.

PKG=example.testy.score
CLS=$PKG.DeadlineScoreTest
SCORE=src/main/java/example/testy/score/DeadlineScore.java
TEST_DIR=src/test/java/example/testy/score
TEST=$TEST_DIR/DeadlineScoreTest.java
DEADLINE='2026-10-12T21:00:00Z'
T1=beforeDeadlineGetsFull
T2=onDeadlineIsStillOnTime
T3=lateWithinDayGetsHalf
T4=lateByMoreThanDayGetsNothing
NAME4='опоздал больше чем на сутки — ноль'

# Строка вывода целиком, как в статье; пробелы в конце строки не в счёт. Аргументы: вывод, строка, пояснение.
# grep без -q: читает вывод до конца, и sed в конвейере не падает по SIGPIPE (run_examples.sh — с pipefail).
expect_line() {
    if sed 's/[[:space:]]*$//' <<<"$1" | grep -xF -- "$2" >/dev/null; then pass "$3"; else fail "$3: нет строки «$2»"; fi
}

# Итог «Tests run: …» из раздела Results и строка BUILD — для сводки. Аргумент: вывод mvn.
summary_lines() { grep -E '^\[(INFO|ERROR)\] (Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+ *$|BUILD )' <<<"$1"; }

# Строка итога класса: «Tests run: N, Failures: F, … in класс». Аргументы: вывод, класс, N, F, пояснение.
expect_class_line() {
    expect_regex "$1" "Tests run: $3, Failures: $4, Errors: 0, Skipped: 0, Time elapsed: .* in ${2//./\\.}[[:space:]]*\$" "$5"
}

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

# Какие из четырёх тестов красные: эти названы в журнале, остальных в нём нет.
# Аргументы: вывод mvn, красные через пробел.
expect_red() {
    local t
    for t in "$T1" "$T2" "$T3" "$T4"; do
        if [[ " $2 " == *" $t "* ]]; then
            expect_contains "$1" "DeadlineScoreTest.$t" "красный $t"
        else
            expect_not_contains "$1" "$t" "$t зелёный — в журнале его нет"
        fi
    done
}

# Правка варианта должна лечь. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    pass "в варианте: $3"
}

# Поломка DeadlineScore и запуск одного класса, как в части 4: «поменял — запустил класс».
# Аргументы: имя варианта, правка perl, что правили. Путь варианта — в $v, вывод mvn — в $out, код — в $code.
break_and_run() {
    v=$(make_variant "$1")
    perl -pi -e "$2" "$v/$SCORE"
    out=""; code=0
    expect_changed "$v/$SCORE" "$SCORE" "$3" || return 1
    out=$(cd "$v" && mvn -B -ntp test -Dtest=DeadlineScoreTest 2>&1); code=$?
}

# Тестовый класс варианта в пакете статьи. Аргументы: папка варианта, имя класса, текст класса после package.
put_class() {
    printf 'package %s;\n\n%s\n' "$PKG" "$3" >"$1/$TEST_DIR/$2.java"
}

# Тест в стиле JUnit 4 из интернета: import org.junit.Test, public у класса и метода, Assert.assertEquals.
JUNIT4_CLASS="import org.junit.Test;

import java.time.Instant;

import static org.junit.Assert.assertEquals;

// Вариант для checks.sh: тест в стиле JUnit 4 из примеров в интернете. В статью не идёт.
public class OldStyleTest {

    @Test
    public void onDeadline() {
        Instant deadline = Instant.parse(\"$DEADLINE\");

        assertEquals(100, DeadlineScore.score(deadline, deadline));
    }
}"

section "Файл теста — там и такой, как показывает статья"
expect_file "$TEST"
expect_file "$SCORE"
expect_file "src/main/java/example/testy/score/ManualCheck.java"
expect_file "src/test/java/example/testy/TestyApplicationTests.java"
src=$(cat "$TEST")
expect_contains "$src" "package $PKG;" "тест — в том же пакете, что и DeadlineScore"
expect_regex "$src" "^class DeadlineScoreTest \{" "класс без public"
expect_not_contains "$src" "public " "ни класс, ни методы не public"
expect_contains "$src" "private static final Instant DEADLINE = Instant.parse(\"$DEADLINE\");" "срок — константа DEADLINE"
n=$(grep -c '^    @Test$' <<<"$src")
if [ "$n" -eq 4 ]; then pass "тестов в классе четыре"; else fail "тестов в классе $n, ждали 4"; fi
dn=$(grep -A 1 '@DisplayName' <<<"$src")
if [ "$(grep -c '@DisplayName' <<<"$src")" -eq 1 ] && grep -q "void $T4()" <<<"$dn"; then
    pass "@DisplayName — один, над $T4"
else
    fail "@DisplayName: ждали один, над $T4"
fi
expect_contains "$src" "@DisplayName(\"$NAME4\")" "русское имя — «$NAME4»"
expect_not_contains "$src" "DeadlineScore.FULL" "ожидания — числа, а не DeadlineScore.FULL"

section "Зелёный отчёт Maven: пять тестов, строка на класс, имён тестов нет"
out=$(mvn -B -ntp test 2>&1); code=$?
expect_ok "$code" "mvn test"
expect_line "$out" "[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 5 — четыре наших и contextLoads"
expect_line "$out" "[INFO] BUILD SUCCESS" "BUILD SUCCESS"
expect_line "$out" "[INFO] Running $CLS" "строка Running $CLS"
expect_class_line "$out" "$CLS" 4 0 "под ней итог класса: Tests run: 4"
suite_ok . "$CLS" 4
suite_ok . example.testy.TestyApplicationTests 1
for t in "$T1" "$T2" "$T3" "$T4"; do
    expect_not_contains "$out" "$t" "имени $t в зелёном журнале нет"
done
expect_not_contains "$out" "$NAME4" "русского имени в журнале нет"
report=$(cat "target/surefire-reports/TEST-$CLS.xml" 2>/dev/null)
expect_contains "$report" "name=\"$T4" "в отчёте Surefire тест назван именем метода"
expect_not_contains "$report" "$NAME4" "русского имени в отчёте по умолчанию нет"
show "$(grep -E "Running $CLS|in $CLS" <<<"$out")"
show "$(summary_lines "$out")"

section "-Dtest: один класс и один тест"
out=$(mvn -B -ntp test -Dtest=DeadlineScoreTest 2>&1); code=$?
expect_ok "$code" "mvn test -Dtest=DeadlineScoreTest"
expect_line "$out" "[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0" "класс: Tests run: 4"
expect_not_contains "$out" "TestyApplicationTests" "тест от Initializr не запускался"
show "$(summary_lines "$out")"
out=$(mvn -B -ntp test "-Dtest=DeadlineScoreTest#$T3" 2>&1); code=$?
expect_ok "$code" "mvn test -Dtest=DeadlineScoreTest#$T3"
expect_line "$out" "[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0" "один тест: Tests run: 1"
suite_ok . "$CLS" 1
expect_contains "$(cat "target/surefire-reports/TEST-$CLS.xml" 2>/dev/null)" "name=\"$T3" "запущен именно $T3"
show "$(summary_lines "$out")"

section "Первый return FULL → return HALF: красные оба теста полного балла"
if break_and_run m7-full-to-half 's/return FULL;/return HALF;/' "первый return FULL; → return HALF;"; then
    expect_failed "$code" "mvn test -Dtest=DeadlineScoreTest"
    expect_line "$out" "[ERROR] Tests run: 4, Failures: 2, Errors: 0, Skipped: 0" "Failures: 2"
    expect_red "$out" "$T1 $T2"
    expect_line "$out" "expected: 100" "expected: 100"
    expect_line "$out" " but was: 50" " but was: 50"
    show "$(summary_lines "$out")"
fi

section "return HALF → return FULL: красный lateWithinDayGetsHalf"
if break_and_run m3-half-to-full 's/return HALF;/return FULL;/' "return HALF; → return FULL;"; then
    expect_failed "$code" "mvn test -Dtest=DeadlineScoreTest"
    expect_line "$out" "[ERROR] Tests run: 4, Failures: 1, Errors: 0, Skipped: 0" "Failures: 1"
    expect_red "$out" "$T3"
    expect_line "$out" "expected: 50" "expected: 50"
    expect_line "$out" " but was: 100" " but was: 100"
    show "$(summary_lines "$out")"
fi

section "return NONE → return HALF: красный lateByMoreThanDayGetsNothing, Maven зовёт его именем метода"
if break_and_run m6-none-to-half 's/return NONE;/return HALF;/' "return NONE; → return HALF;"; then
    expect_failed "$code" "mvn test -Dtest=DeadlineScoreTest"
    expect_line "$out" "[ERROR] Tests run: 4, Failures: 1, Errors: 0, Skipped: 0" "Failures: 1"
    expect_red "$out" "$T4"
    expect_not_contains "$out" "$NAME4" "русского имени в журнале нет — только имя метода"
    expect_line "$out" "expected: 0" "expected: 0"
    expect_line "$out" " but was: 50" " but was: 50"
    show "$(grep -m 1 -B 1 -A 2 -E '^expected: 0' <<<"$out")"
fi

section "isBefore вместо !isAfter (статья 1): из четырёх красный только onDeadlineIsStillOnTime"
if break_and_run m1-is-before 's/if \(!submittedAt\.isAfter\(deadline\)\) \{/if (submittedAt.isBefore(deadline)) {/' \
    "if (submittedAt.isBefore(deadline))"; then
    expect_failed "$code" "mvn test -Dtest=DeadlineScoreTest"
    expect_line "$out" "[ERROR] Tests run: 4, Failures: 1, Errors: 0, Skipped: 0" "Failures: 1"
    expect_red "$out" "$T2"
    expect_line "$out" "expected: 100" "expected: 100"
    expect_line "$out" " but was: 50" " but was: 50"
    show "$(summary_lines "$out")"
fi

section "Сутки → 23 часа: все зелёные — между 23-м и 24-м часом никто не сдаёт"
v=$(make_variant grace-23h)
perl -pi -e 's/Duration\.ofHours\(24\)/Duration.ofHours(23)/' "$v/$SCORE"
if expect_changed "$v/$SCORE" "$SCORE" "Duration.ofHours(23)"; then
    out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
    expect_ok "$code" "mvn test с 23 часами"
    expect_line "$out" "[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0" "всё зелёное"
    show "$(summary_lines "$out")"
fi

section "FULL = 10: тесты с числом 100 красные, тест с DeadlineScore.FULL согласен с ошибкой"
v=$(make_variant full-10)
perl -pi -e 's/public static final int FULL = 100;/public static final int FULL = 10;/' "$v/$SCORE"
if expect_changed "$v/$SCORE" "$SCORE" "FULL = 10"; then
    sed -e 's/^class DeadlineScoreTest {/class ConstTest {/' -e 's/isEqualTo(100)/isEqualTo(DeadlineScore.FULL)/' \
        "$TEST" >"$v/$TEST_DIR/ConstTest.java"
    expect_contains "$(cat "$v/$TEST_DIR/ConstTest.java")" "assertThat(score).isEqualTo(DeadlineScore.FULL);" \
        "ConstTest — те же тесты, ожидание через DeadlineScore.FULL"
    out=$(cd "$v" && mvn -B -ntp test -Dtest=DeadlineScoreTest,ConstTest 2>&1); code=$?
    expect_failed "$code" "mvn test с FULL = 10"
    expect_line "$out" "[ERROR] Tests run: 8, Failures: 2, Errors: 0, Skipped: 0" "Tests run: 8, Failures: 2"
    expect_red "$out" "$T1 $T2"
    expect_line "$out" "expected: 100" "expected: 100"
    expect_line "$out" " but was: 10" " but was: 10"
    suite_ok "$v" "$PKG.ConstTest" 4
    show "$(summary_lines "$out")"
fi

section "Тест из интернета на JUnit 4 не компилируется: cannot find symbol — класса Test в org.junit нет"
v=$(make_variant junit4-import)
put_class "$v" OldStyleTest "$JUNIT4_CLASS"
out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
expect_failed "$code" "mvn test с import org.junit.Test"
expect_contains "$out" "cannot find symbol" "cannot find symbol — как в статье"
expect_contains "$out" "symbol:   class Test" "…символ — класс Test"
expect_contains "$out" "location: package org.junit" "…в пакете org.junit: пакет компилятор находит"
expect_not_contains "$out" "package org.junit does not exist" "«package org.junit does not exist» нет — JUnit 6 лежит в org.junit.jupiter"
show "$(grep -m 3 -E 'cannot find symbol|symbol: +class Test|location: package org.junit' <<<"$out")"

section "assertThat из Hamcrest: строка AssertJ не компилируется"
v=$(make_variant hamcrest)
put_class "$v" HamcrestTest "import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.hamcrest.MatcherAssert.assertThat;

// Вариант для checks.sh: IDE подставила assertThat из Hamcrest. В статью не идёт.
class HamcrestTest {

    @Test
    void onDeadline() {
        Instant deadline = Instant.parse(\"$DEADLINE\");

        int score = DeadlineScore.score(deadline, deadline);

        assertThat(score).isEqualTo(100);
    }
}"
out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
expect_failed "$code" "mvn test с org.hamcrest.MatcherAssert.assertThat"
expect_contains "$out" "no suitable method found for assertThat(int)" "no suitable method found for assertThat(int)"
show "$(grep -m 1 'no suitable method found' <<<"$out")"

section "@DisplayName «это настраивается»: с настройкой Surefire русское имя — в отчёте"
v=$(make_variant display-names)
# shellcheck disable=SC2016  # $1 и $2 — группы perl, а не переменные bash
perl -0pi -e 's#(\n( *)<plugins>\n)#$1$2    <plugin>\n$2        <groupId>org.apache.maven.plugins</groupId>\n$2        <artifactId>maven-surefire-plugin</artifactId>\n$2        <configuration>\n$2            <statelessTestsetReporter implementation="org.apache.maven.plugin.surefire.extensions.junit5.JUnit5Xml30StatelessReporter">\n$2                <usePhrasedTestCaseMethodName>true</usePhrasedTestCaseMethodName>\n$2            </statelessTestsetReporter>\n$2        </configuration>\n$2    </plugin>\n#' "$v/pom.xml"
if expect_changed "$v/pom.xml" pom.xml "в pom.xml отчёт Surefire с usePhrasedTestCaseMethodName"; then
    out=$(cd "$v" && mvn -B -ntp test -Dtest=DeadlineScoreTest 2>&1); code=$?
    expect_ok "$code" "mvn test с настройкой отчёта"
    report=$(cat "$v/target/surefire-reports/TEST-$CLS.xml" 2>/dev/null)
    expect_contains "$report" "name=\"$NAME4\"" "в отчёте тест назван «$NAME4»"
    show "$(grep -o '<testcase name="[^"]*"' <<<"$report")"
fi

section "JUnit 4 приехал с чужой библиотекой: запустит ли его сборка без Vintage"
v=$(make_variant junit4-transitive)
# shellcheck disable=SC2016  # $1 и $2 — группы perl, а не переменные bash
perl -0pi -e 's#(\n( *)</dependencies>)#\n$2    <dependency>\n$2        <groupId>junit</groupId>\n$2        <artifactId>junit</artifactId>\n$2        <version>4.13.2</version>\n$2        <scope>test</scope>\n$2    </dependency>$1#' "$v/pom.xml"
if expect_changed "$v/pom.xml" pom.xml "в pom.xml junit:junit:4.13.2, без Vintage"; then
    put_class "$v" OldStyleTest "$JUNIT4_CLASS"
    out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
    expect_ok "$code" "mvn test: тест JUnit 4 компилируется"
    if grep -qs '<testcase name="onDeadline' "$v/target/surefire-reports/TEST-$PKG.OldStyleTest.xml"; then
        note "Surefire запустил тест JUnit 4 без Vintage в pom — «скорее всего, не запустит» в части 1 поправить"
    else
        pass "OldStyleTest не запущен: сборка его не видит"
        expect_line "$out" "[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 5 — тестов не прибавилось"
    fi
    show "$(summary_lines "$out")"
fi

section "Ссылки статьи открываются"
for link in https://docs.junit.org/6.0.3/writing-tests/test-classes-and-methods.html \
    https://docs.junit.org/6.0.3/writing-tests/display-names.html \
    https://docs.junit.org/6.0.3/migrating-from-junit4.html \
    https://assertj.github.io/doc/ \
    https://maven.apache.org/surefire/maven-surefire-plugin/examples/junit-platform.html \
    https://hammerhall.io/ledger/testing/1-why-tests \
    https://hammerhall.io/ledger/articles/0-before-spring; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
