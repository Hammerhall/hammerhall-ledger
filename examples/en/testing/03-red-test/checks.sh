# Английская редакция статьи 3 серии «От красного к зелёному» (en/testing/03-red-test.md).
# Те же проверки, что у русской, со строками программы и кусками текста по-английски.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница testy — после статьи 2: ManualCheck из статьи 1, DeadlineScore после починки — тот же, что в статье 1,
# DeadlineScoreTest статьи 3 (четыре теста статьи 2 и два новых) заменил тест статьи 2. В mvn verify он уже прошёл.
# Версия коллеги из части 1 и фрагменты «так не пишут» — ErrorTest и ZoneTest — в песочницу не кладутся: их берут
# из текста статьи и кладут в варианты. Здесь — то, что статья обещает словами: итог «Tests run: 7»; шесть тестов
# зелёные в любом поясе; с версией коллеги четыре теста статьи 2 зелёные, оба новых красные (expected: 50 /
# but was: 100, строки 61 и 73 — и в итогах Maven, и в стеке), а сутки и полчаса дают 50 вместо нуля; ErrorTest —
# Errors, а не Failures, стек DeadlineScore.java:24 и ErrorTest.java:16, «Deadline is not set» в *.txt и TEST-*.xml;
# grep 'Caused by:' по этим отчётам пуст, а одна причина из двух отчётов — одна строка (без -h — две); ZoneTest
# зелёный по Москве и красный по UTC; @Disabled — Skipped и зелёная сборка; подогнанное ожидание зелёное с ошибкой
# и красное после починки; ссылки открываются.

PKG=example.testy.score
CLS=$PKG.DeadlineScoreTest
SCORE=src/main/java/example/testy/score/DeadlineScore.java
TEST_DIR=src/test/java/example/testy/score
TEST=$TEST_DIR/DeadlineScoreTest.java
REPORTS=target/surefire-reports
ARTICLE=${ROOT:-}/en/testing/03-red-test.md
ARTICLE1=${ROOT:-}/en/testing/01-why-tests.md
ARTICLE2=${ROOT:-}/en/testing/02-first-test.md
OLD4="beforeDeadlineGetsFull onDeadlineIsStillOnTime lateWithinDayGetsHalf lateByMoreThanDayGetsNothing"
T5=twentyMinutesLateGetsHalf
T6=halfAnHourAfterMoscowMidnightIsLate
L5=61                                   # строки assertThat этих тестов — как в статье
L6=73
BUGGY_HEAD='// src/main/java/example/testy/score/DeadlineScore.java — version after the "simplification"'
ERROR_HEAD='// fragment: a test that never reached its check — Errors'
ZONE_HEAD='// fragment: a test that is green on your machine and red in the build'
GREP_CAUSES='Caused by:[^<&]\{0,250\}'      # рецепт части 2

# Строка вывода целиком, как в статье; пробелы в конце строки не в счёт. Аргументы: вывод, строка, пояснение.
# grep без -q: читает вывод до конца, и sed в конвейере не падает по SIGPIPE (run_examples.sh — с pipefail).
expect_line() {
    if sed 's/[[:space:]]*$//' <<<"$1" | grep -xF -- "$2" >/dev/null; then pass "$3"; else fail "$3: нет строки «$2»"; fi
}

# Итог «Tests run: …» из раздела Results и строка BUILD — для сводки. Аргумент: вывод mvn.
# С пропущенными тестами Surefire пишет итог уровнем WARNING.
summary_lines() {
    grep -E '^\[(INFO|WARNING|ERROR)\] (Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+ *$|BUILD )' <<<"$1"
}

# Отчёт Surefire о классе: «тестов N, все зелёные». Аргументы: папка проекта, класс, N.
suite_ok() {
    local head
    head=$(grep -m 1 '<testsuite' "$1/$REPORTS/TEST-$2.xml" 2>/dev/null)
    if grep -q "tests=\"$3\"" <<<"$head" && grep -q 'failures="0"' <<<"$head" \
        && grep -q 'errors="0"' <<<"$head" && grep -q 'skipped="0"' <<<"$head"; then
        pass "$2: тестов $3, все зелёные"
    else
        fail "$2: ждали $3 зелёных — ${head:-отчёта нет}"
    fi
}

# Правка варианта должна лечь. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    pass "в варианте: $3"
}

# Блок кода статьи, который начинается с этой строки. Аргументы: файл статьи, первая строка блока,
# all — первый такой во всём тексте, full — первый в «The full example, with imports».
block_from() {
    awk -v first="$2" -v where="$3" 'where == "full" && /^## The full example/ { on = 1; next }
        where == "full" && !on { next }
        /^```/ && !inside { inside = 1; buf = ""; n = 0; next }
        inside && /^```$/ { inside = 0; if (keep) { printf "%s", buf; exit } next }
        inside { if (n == 0) keep = ($0 == first); buf = buf $0 "\n"; n++ }' "$1"
}

# Кусок кода из текста статьи — строка в строку из файла (пустые строки и «// …» не в счёт).
# Аргументы: первая строка куска, файл, что за кусок.
expect_snippet() {
    local snippet missing
    snippet=$(block_from "$ARTICLE" "$1" all)
    if [ -z "$snippet" ] || [ ! -s "$2" ]; then fail "$3: куска нет в статье или файла нет в примере"; return; fi
    missing=$(grep -v -e '^$' -e '// …$' <<<"$snippet" | grep -vxF -f "$2")
    if [ -z "$missing" ]; then
        pass "$3 — те же строки, что в «Пример целиком»"
    else
        fail "$3: этих строк нет в файле"
        show "$missing"
    fi
}

# Какой метод теста стоит на строке файла. Аргументы: файл, номер строки.
method_at() { awk -v l="$2" 'NR <= l && /^    void [A-Za-z]+\(\)/ { m = $2 } NR == l { print m; exit }' "$1"; }

# Первые строки «at» стека упавшего теста в журнале Maven. Аргументы: вывод mvn, имя метода, сколько строк.
stack_of() {
    awk -v t="$2" -v n="$3" '$0 ~ ("[. ]" t "[ (]") && index($0, "<<< ") { on = 1; next }
        on && /^[[:space:]]+at / { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; if (++k == n) exit }' <<<"$1"
}

# Вариант с версией коллеги из части 1: проверки после null заменены её строками из статьи.
# Аргумент: имя варианта. Путь варианта — в $v; код 1 — правка не легла.
colleague() {
    local buggy
    v=$(make_variant "$1")
    buggy=$(block_from "$ARTICLE" "$BUGGY_HEAD" all | sed -n '/long hoursLate/,/return NONE;/p')
    # shellcheck disable=SC2016  # $ENV{BUGGY} — переменная perl, а не bash
    BUGGY="$buggy"$'\n' perl -0pi -e \
        's/^        if \(!submittedAt\.isAfter\(deadline\)\) \{.*?^        return NONE;\n/$ENV{BUGGY}/ms' "$v/$SCORE"
    expect_changed "$v/$SCORE" "$SCORE" "версия коллеги из статьи: Duration.between(…).toHours()" || return 1
    if grep -qF 'if (hoursLate <= GRACE.toHours()) {' "$v/$SCORE"; then return 0; fi
    fail "версия коллеги легла не целиком"
    return 1
}

section "Код статьи: DeadlineScore — как в статье 1, тест — четыре теста статьи 2 и два новых"
expect_file "$SCORE"
expect_file "$TEST"
if [ -e "$TEST_DIR/ErrorTest.java" ] || [ -e "$TEST_DIR/ZoneTest.java" ]; then
    fail "фрагменты ErrorTest и ZoneTest попали в песочницу"
else
    pass "фрагменты ErrorTest и ZoneTest в песочницу не попали — только в опыты"
fi
n=$(grep -c '^    @Test$' "$TEST")
if [ "$n" -eq 6 ]; then pass "тестов в DeadlineScoreTest шесть"; else fail "тестов в DeadlineScoreTest $n, ждали 6"; fi
for pair in "$L5:$T5" "$L6:$T6"; do
    line=${pair%%:*} t=${pair#*:}
    if [ "$(method_at "$TEST" "$line")" = "$t()" ] \
        && [ "$(sed -n "${line}p" "$TEST")" = "        assertThat(score).isEqualTo(50);" ]; then
        pass "строка $line файла — assertThat теста $t"
    else
        fail "строка $line файла — не assertThat теста $t: $(sed -n "${line}p" "$TEST")"
    fi
done
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    one=$(block_from "$ARTICLE1" "// src/main/java/example/testy/score/DeadlineScore.java" full)
    if [ -n "$one" ] && [ "$one" = "$(cat "$SCORE")" ]; then
        pass "DeadlineScore после починки — слово в слово из статьи 1"
    else
        fail "DeadlineScore расходится со статьёй 1"
    fi
    two=$(block_from "$ARTICLE2" "// src/test/java/example/testy/score/DeadlineScoreTest.java" full)
    missing=$(grep -v '^$' <<<"$two" | grep -vxF -f "$TEST")
    if [ -n "$two" ] && [ -z "$missing" ]; then
        pass "каждая строка теста статьи 2 — в тесте статьи 3: четыре теста не тронуты"
    else
        fail "строк теста статьи 2 нет в тесте статьи 3"
        show "$missing"
    fi
    mkdir -p target
    block_from "$ARTICLE" "$ERROR_HEAD" full >target/ErrorTest.java.txt
    block_from "$ARTICLE" "$ZONE_HEAD" full >target/ZoneTest.java.txt
    expect_snippet "    @Test" "$TEST" "тест на жалобу в части 1"
    expect_snippet "        if (!submittedAt.isAfter(deadline)) {                   // exactly on the deadline is still on time" \
        "$SCORE" "починка в части 1"
    expect_snippet "$ERROR_HEAD" target/ErrorTest.java.txt "ErrorTest в части 2"
    expect_snippet "$ZONE_HEAD" target/ZoneTest.java.txt "ZoneTest в части 3"
    expect_snippet '                .atStartOfDay(ZoneId.of("Europe/Moscow"))                   // time zone named explicitly' \
        "$TEST" "пояс по имени в части 3"
fi

section "Итог Maven: семь тестов — шесть DeadlineScoreTest и тест от start.spring.io"
out=$(mvn -B -ntp test 2>&1); code=$?
expect_ok "$code" "mvn test"
expect_line "$out" "[INFO] Tests run: 7, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 7, всё зелёное"
suite_ok . "$CLS" 6
suite_ok . example.testy.TestyApplicationTests 1
expect_file "$REPORTS/$CLS.txt"
expect_file "$REPORTS/TEST-$CLS.xml"
show "$(summary_lines "$out")"

section "После починки шесть тестов зелёные в любом поясе"
note "пояс машины сборки: $(date '+%Z %z')"
for zone in Europe/Moscow UTC America/New_York; do
    out=$(mvn -B -ntp test -Dtest=DeadlineScoreTest "-DargLine=-Duser.timezone=$zone" 2>&1); code=$?
    expect_ok "$code" "mvn test -Dtest=DeadlineScoreTest -DargLine=-Duser.timezone=$zone"
    expect_line "$out" "[INFO] Tests run: 6, Failures: 0, Errors: 0, Skipped: 0" "$zone: Tests run: 6, всё зелёное"
done

section "Версия коллеги: четыре теста статьи 2 зелёные, оба новых красные; сутки и полчаса — 50"
if colleague colleague; then
    cat >"$v/$TEST_DIR/EdgeProbeTest.java" <<EOF
package $PKG;

import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

// Вариант для checks.sh: мысль вдогонку из части 1 — опоздал на сутки и полчаса. В статью не идёт.
class EdgeProbeTest {

    @Test
    void dayAndHalfAnHourLateGetsNothing() {
        Instant deadline = Instant.parse("2026-10-12T21:00:00Z");

        int score = DeadlineScore.score(deadline, deadline.plus(Duration.ofHours(24).plusMinutes(30)));

        assertThat(score).isEqualTo(0);
    }
}
EOF
    out=$(cd "$v" && mvn -B -ntp test -Dtest=DeadlineScoreTest,EdgeProbeTest 2>&1); code=$?
    expect_failed "$code" "mvn test с версией коллеги"
    expect_line "$out" "[ERROR] Tests run: 7, Failures: 3, Errors: 0, Skipped: 0" \
        "Failures: 3 — два новых теста и проба «сутки и полчаса»"
    for t in $OLD4; do expect_not_contains "$out" "$t" "$t зелёный — в журнале его нет"; done
    expect_regex "$out" "^\[ERROR\]   DeadlineScoreTest\.$T5:$L5( |\$)" "в итогах: DeadlineScoreTest.$T5:$L5"
    expect_regex "$out" "^\[ERROR\]   DeadlineScoreTest\.$T6:$L6( |\$)" "в итогах: DeadlineScoreTest.$T6:$L6"
    expect_line "$out" "expected: 50" "expected: 50"
    expect_line "$out" " but was: 100" " but was: 100"
    for pair in "$L5:$T5" "$L6:$T6"; do
        line=${pair%%:*} t=${pair#*:}
        at=$(stack_of "$out" "$t" 1)
        want="at $CLS.$t(DeadlineScoreTest.java:$line)"
        if [ "$at" = "$want" ]; then pass "в стеке первая строка at — $want"; else fail "первая строка at у $t: «$at»"; fi
    done
    expect_contains "$out" "EdgeProbeTest.dayAndHalfAnHourLateGetsNothing" "сутки и полчаса: красная проба"
    expect_line "$out" "expected: 0" "expected: 0"
    expect_line "$out" " but was: 50" " but was: 50 — у коллеги 24 целых часа «не больше 24»"
    show "$(sed -n '/^\[ERROR\] Failures:/,/^\[INFO\] *$/p' <<<"$out")"
    show "$(grep -m 1 -A 4 -E "[. ]$T5 .*<<< " <<<"$out")"
fi

section "ErrorTest: исключение до проверки — Errors, а не Failures; отчёты в target/surefire-reports"
v=$(make_variant error-test)
block_from "$ARTICLE" "$ERROR_HEAD" full >"$v/$TEST_DIR/ErrorTest.java"
expect_contains "$(cat "$v/$TEST_DIR/ErrorTest.java")" "class ErrorTest {" "ErrorTest взят из «Пример целиком»"
expect_contains "$(sed -n 16p "$v/$TEST_DIR/ErrorTest.java")" "DeadlineScore.score(null, submittedAt);" \
    "строка 16 файла — вызов score(null, …)"
out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
expect_failed "$code" "mvn test с ErrorTest"
expect_line "$out" "[ERROR] Tests run: 8, Failures: 0, Errors: 1, Skipped: 0" "Tests run: 8 — Errors: 1, Failures: 0"
expect_contains "$out" "java.lang.IllegalArgumentException" "в журнале — IllegalArgumentException"
at=$(stack_of "$out" forgotTheDeadline 2)
want="at $PKG.DeadlineScore.score(DeadlineScore.java:24)
at $PKG.ErrorTest.forgotTheDeadline(ErrorTest.java:16)"
if [ "$at" = "$want" ]; then pass "стек: где выброшено — DeadlineScore.java:24, кто позвал — ErrorTest.java:16"
else fail "первые строки at: $(tr '\n' ' ' <<<"$at")"; fi
txt=$(cat "$v/$REPORTS/$PKG.ErrorTest.txt" 2>/dev/null)
xml=$(cat "$v/$REPORTS/TEST-$PKG.ErrorTest.xml" 2>/dev/null)
expect_contains "$txt" "Tests run: 1, Failures: 0, Errors: 1, Skipped: 0" "*.txt — сводка: Errors: 1"
expect_contains "$txt" "java.lang.IllegalArgumentException: Deadline is not set" "*.txt — исключение и наш текст"
expect_contains "$txt" "at $PKG.ErrorTest.forgotTheDeadline(ErrorTest.java:16)" "*.txt — стек упавшего теста"
expect_contains "$xml" 'type="java.lang.IllegalArgumentException"' "TEST-*.xml — тип исключения"
expect_contains "$xml" "Deadline is not set" "TEST-*.xml — наш текст"
expect_contains "$xml" "at $PKG.DeadlineScore.score(DeadlineScore.java:24)" "TEST-*.xml — стек"
causes=$(cd "$v" && grep -ho "$GREP_CAUSES" "$REPORTS"/TEST-*.xml | sort -u)
if [ -z "$causes" ]; then pass "grep 'Caused by:' ничего не вывел: у исключения нет причины"
else fail "grep 'Caused by:' вывел: $causes"; fi
note "строк org.junit в стеке *.txt: $(grep -c '^[[:space:]]*at org\.junit' <<<"$txt")"
show "$(head -n 12 <<<"$txt")"

section "Рецепт grep: одна причина из двух отчётов — одна строка, без -h — две"
v=$(make_variant caused-by)
for name in WrappedOneTest WrappedTwoTest; do
    cat >"$v/$TEST_DIR/$name.java" <<EOF
package $PKG;

import org.junit.jupiter.api.Test;

import java.time.Instant;

// Вариант для checks.sh: исключение с причиной — в отчёте будет «Caused by:». В статью не идёт.
class $name {

    @Test
    void wrapsTheCause() {
        try {
            DeadlineScore.score(null, Instant.parse("2026-10-12T21:00:00Z"));
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException("score not calculated", e);
        }
    }
}
EOF
done
out=$(cd "$v" && mvn -B -ntp test -Dtest=WrappedOneTest,WrappedTwoTest 2>&1); code=$?
expect_failed "$code" "mvn test: два теста упали по одной причине"
expect_line "$out" "[ERROR] Tests run: 2, Failures: 0, Errors: 2, Skipped: 0" "Errors: 2"
causes=$(cd "$v" && grep -ho "$GREP_CAUSES" "$REPORTS"/TEST-*.xml | sort -u)
expect_line "$causes" "Caused by: java.lang.IllegalArgumentException: Deadline is not set" "с -h: причина найдена"
n=$(grep -c . <<<"$causes")
if [ "$n" -eq 1 ]; then pass "с -h — одна строка на два отчёта"; else fail "с -h — строк $n, ждали одну"; fi
n=$(cd "$v" && grep -o "$GREP_CAUSES" "$REPORTS"/TEST-*.xml | sort -u | grep -c .)
if [ "$n" -eq 2 ]; then pass "без -h — две строки: перед каждой имя файла"; else fail "без -h — строк $n, ждали две"; fi
show "$causes"

section "ZoneTest: зелёный по Москве, красный по UTC — команда из статьи"
v=$(make_variant zone-test)
block_from "$ARTICLE" "$ZONE_HEAD" full >"$v/$TEST_DIR/ZoneTest.java"
expect_contains "$(cat "$v/$TEST_DIR/ZoneTest.java")" "class ZoneTest {" "ZoneTest взят из «Пример целиком»"
out=$(cd "$v" && mvn -B -ntp test -Dtest=ZoneTest -DargLine=-Duser.timezone=Europe/Moscow 2>&1); code=$?
expect_ok "$code" "mvn test -Dtest=ZoneTest -DargLine=-Duser.timezone=Europe/Moscow"
expect_line "$out" "[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0" "по Москве оба зелёные"
out=$(cd "$v" && mvn -B -ntp test -Dtest=ZoneTest -DargLine=-Duser.timezone=UTC 2>&1); code=$?
expect_failed "$code" "mvn test -Dtest=ZoneTest -DargLine=-Duser.timezone=UTC"
expect_line "$out" "[ERROR] Tests run: 2, Failures: 1, Errors: 0, Skipped: 0" "по UTC — Failures: 1"
expect_contains "$out" "ZoneTest.halfAnHourAfterMidnightIsLate" "красный — тест с ZoneId.systemDefault()"
expect_not_contains "$out" "ZoneTest.halfAnHourAfterMoscowMidnightIsLate" "тест с Europe/Moscow зелёный"
expect_line "$out" "expected: 50" "expected: 50"
expect_line "$out" " but was: 100" " but was: 100"
show "$(summary_lines "$out")"

section "Спрятать красное: @Disabled — Skipped и зелёная сборка с ошибкой в коде"
if colleague disabled; then
    perl -0pi -e 's/(import org\.junit\.jupiter\.api\.DisplayName;\n)/import org.junit.jupiter.api.Disabled;\n$1/;
        s/(    \@Test\n)(    void (?:twentyMinutesLateGetsHalf|halfAnHourAfterMoscowMidnightIsLate)\(\))/$1    \@Disabled\n$2/g' \
        "$v/$TEST"
    n=$(grep -c '^    @Disabled$' "$v/$TEST")
    if [ "$n" -eq 2 ]; then pass "в варианте: @Disabled над двумя новыми тестами"; else fail "@Disabled в варианте: $n"; fi
    out=$(cd "$v" && mvn -B -ntp test -Dtest=DeadlineScoreTest 2>&1); code=$?
    expect_ok "$code" "mvn test: версия коллеги и @Disabled"
    expect_regex "$out" '^\[(INFO|WARNING)\] Tests run: 6, Failures: 0, Errors: 0, Skipped: 2 *$' "отключённые — в Skipped"
    expect_line "$out" "[INFO] BUILD SUCCESS" "BUILD SUCCESS — а ошибка в коде осталась"
    show "$(summary_lines "$out")"
fi

section "Спрятать красное: подогнанное ожидание зелёное с ошибкой и красное после починки"
if colleague fitted; then
    # shellcheck disable=SC2016  # ${1} и $2 — группы perl, а не переменные bash
    perl -0pi -e 's/(void twentyMinutesLateGetsHalf\(\) \{.*?isEqualTo\()50(\);)/${1}100$2/s' "$v/$TEST"
    if expect_changed "$v/$TEST" "$TEST" "в $T5 ожидание 50 → 100"; then
        out=$(cd "$v" && mvn -B -ntp test "-Dtest=DeadlineScoreTest#$T5" 2>&1); code=$?
        expect_ok "$code" "подогнанный тест с версией коллеги"
        expect_line "$out" "[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0" "зелёный — охраняет ошибку"
        cp "$SCORE" "$v/$SCORE"
        out=$(cd "$v" && mvn -B -ntp test "-Dtest=DeadlineScoreTest#$T5" 2>&1); code=$?
        expect_failed "$code" "подогнанный тест после починки"
        expect_line "$out" "expected: 100" "expected: 100"
        expect_line "$out" " but was: 50" " but was: 50 — починивший получил красный тест"
    fi
fi

section "Ссылки статьи открываются"
# Ссылки на hammerhall.io — английские адреса, как в статье. Пока английской страницы нет, на сайте открывается
# русская — тогда проверяется она.
http_status() { curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
for link in https://docs.junit.org/6.0.3/writing-tests/disabling-tests.html \
    https://docs.junit.org/6.0.3/running-tests/stack-trace-pruning.html \
    https://maven.apache.org/surefire/maven-surefire-plugin/ \
    https://maven.apache.org/surefire/maven-surefire-plugin/test-mojo.html \
    https://www.martinfowler.com/articles/nonDeterminism.html \
    https://hammerhall.io/en/ledger/testing/1-why-tests \
    https://hammerhall.io/en/ledger/testing/2-first-test \
    https://hammerhall.io/en/ledger/articles/0-before-spring; do
    status=$(http_status "$link"); code=$?
    if [ "$code" -eq 0 ] && [ "$status" -ge 400 ] && [[ $link == https://hammerhall.io/en/* ]]; then
        ru=${link/hammerhall.io\/en\//hammerhall.io/}
        note "$status — $link: английской страницы пока нет, проверяю русскую"
        link=$ru
        status=$(http_status "$link"); code=$?
    fi
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
