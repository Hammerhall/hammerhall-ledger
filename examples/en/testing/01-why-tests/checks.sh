# Английская редакция статьи 1 серии «От красного к зелёному» (en/testing/01-why-tests.md).
# Те же проверки, что у русской, со строками программы и кусками текста по-английски.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница testy со start.spring.io, без зависимостей; код статьи — DeadlineScore, ManualCheck (void main()
# и IO.println, Java 25) и DeadlineScoreTest в example.testy.score. В mvn verify он уже прошёл. Здесь — то,
# что статья обещает словами: ManualCheck печатает 100, 50, 0; итог Maven — «Tests run: 2» и BUILD SUCCESS;
# -Dtest запускает один класс; с isBefore тест красный (expected: 100 / but was: 50, Failures: 1),
# а ManualCheck печатает то же; с сутками в 23 часа тест зелёный — сутки он не проверяет; непойманное
# исключение — Errors, а не Failures; Surefire берёт Test*, *Test, *Tests, *TestCase, а ScoreRulesCheck
# и *IT пропускает молча; свой список <includes> заменяет умолчания; ссылки статьи открываются.

PKG=example.testy.score
SCORE=src/main/java/example/testy/score/DeadlineScore.java
TEST_DIR=src/test/java/example/testy/score
DEADLINE='2026-10-12T21:00:00Z'

# Строка вывода целиком, как в статье; пробелы в конце строки не в счёт. Аргументы: вывод, строка, пояснение.
# Без трубы в grep -q: при pipefail ранний выход grep обрывает sed, и найденная строка считалась бы ненайденной.
expect_line() {
    local trimmed
    trimmed=$(sed 's/[[:space:]]*$//' <<<"$1")
    if grep -qxF -- "$2" <<<"$trimmed"; then pass "$3"; else fail "$3: нет строки «$2»"; fi
}

# Итог «Tests run: …» из раздела Results и строка BUILD — для сводки. Аргумент: вывод mvn.
summary_lines() { grep -E '^\[(INFO|ERROR)\] (Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+ *$|BUILD )' <<<"$1"; }

# Есть ли отчёт Surefire о классе. Аргументы: папка проекта, класс, 1 — должен быть / 0 — не должен, пояснение.
expect_report() {
    if [ -f "$1/target/surefire-reports/TEST-$2.xml" ]; then
        if [ "$3" = 1 ]; then pass "$4"; else fail "$4: Surefire его запустил"; fi
    else
        if [ "$3" = 1 ]; then fail "$4: отчёта нет"; else pass "$4"; fi
    fi
}

# Тестовый класс в пакете статьи: один тест, который проходит (pass) или падает (fail).
# Аргументы: папка варианта, имя класса, pass|fail.
test_class() {
    local expected=100
    [ "$3" = fail ] && expected=0
    cat >"$1/$TEST_DIR/$2.java" <<EOF
package $PKG;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

// Вариант для checks.sh: проверка шаблонов имён Surefire. В статью не идёт.
class $2 {

    @Test
    void onDeadline() {
        Instant deadline = Instant.parse("$DEADLINE");

        assertThat(DeadlineScore.score(deadline, deadline)).isEqualTo($expected);
    }
}
EOF
}

# Правка варианта должна лечь. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    pass "в варианте: $3"
}

section "Файлы — там, где показывает статья"
expect_file "$SCORE"
expect_file "src/main/java/example/testy/score/ManualCheck.java"
expect_file "$TEST_DIR/DeadlineScoreTest.java"
expect_file "src/main/java/example/testy/TestyApplication.java"
expect_file "src/test/java/example/testy/TestyApplicationTests.java"
expect_contains "$(cat "$TEST_DIR/DeadlineScoreTest.java")" "package $PKG;" "тест — в том же пакете, что и класс"

section "ManualCheck: void main() и IO.println на Java 25 печатают 100, 50, 0"
out=$(run_main "$PKG.ManualCheck"); code=$?
expect_ok "$code" "ManualCheck"
printed=$(grep -v '^Picked up' <<<"$out")
if [ "$printed" = $'100\n50\n0' ]; then pass "в консоли 100, 50, 0"; else fail "ждали 100, 50, 0 — пришло: $(tr '\n' ' ' <<<"$printed")"; fi
show "$printed"

section "Итог Maven: два теста — твой и тест от start.spring.io"
out=$(mvn -B -ntp test 2>&1); code=$?
expect_ok "$code" "mvn test"
expect_line "$out" "[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 2, всё зелёное"
expect_line "$out" "[INFO] BUILD SUCCESS" "BUILD SUCCESS"
expect_report . "$PKG.DeadlineScoreTest" 1 "запущен DeadlineScoreTest"
expect_report . example.testy.TestyApplicationTests 1 "запущен TestyApplicationTests"
show "$(summary_lines "$out")"

section "-Dtest=DeadlineScoreTest — один класс"
out=$(mvn -B -ntp test -Dtest=DeadlineScoreTest 2>&1); code=$?
expect_ok "$code" "mvn test -Dtest=DeadlineScoreTest"
expect_line "$out" "[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 1"
expect_not_contains "$out" "TestyApplicationTests" "тест от start.spring.io не запускался"
show "$(summary_lines "$out")"

section "isBefore вместо !isAfter: ManualCheck молчит, тест красный"
v=$(make_variant is-before)
perl -pi -e 's/if \(!submittedAt\.isAfter\(deadline\)\) \{/if (submittedAt.isBefore(deadline)) {/' "$v/$SCORE"
if expect_changed "$v/$SCORE" "$SCORE" "if (submittedAt.isBefore(deadline))"; then
    expect_contains "$(cat "$v/$SCORE")" "!submittedAt.isAfter(deadline.plus(GRACE))" "второе условие не тронуто"
    out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
    expect_failed "$code" "mvn test с isBefore"
    expect_line "$out" "[ERROR] Tests run: 2, Failures: 1, Errors: 0, Skipped: 0" "Tests run: 2, Failures: 1"
    # Maven 3 (обёртка start.spring.io) пишет [INFO] BUILD FAILURE, Maven 4 — [ERROR]; статья — «примерно так».
    expect_regex "$out" '^\[(INFO|ERROR)\] BUILD FAILURE$' "BUILD FAILURE"
    expect_contains "$out" "onDeadlineIsStillOnTime" "красный — тест «ровно в срок»"
    expect_line "$out" "expected: 100" "expected: 100"
    expect_line "$out" " but was: 50" " but was: 50"
    show "$(summary_lines "$out")"
    show "$(grep -m 1 -A 2 -E '^expected: 100' <<<"$out")"
    out=$(cd "$v" && run_main "$PKG.ManualCheck"); code=$?
    expect_ok "$code" "ManualCheck с isBefore"
    printed=$(grep -v '^Picked up' <<<"$out")
    if [ "$printed" = $'100\n50\n0' ]; then pass "ManualCheck печатает то же: 100, 50, 0"; else fail "ManualCheck с isBefore: $(tr '\n' ' ' <<<"$printed")"; fi
fi

section "Сутки → 23 часа: правило сломано, а тест зелёный — сутки он не проверяет"
v=$(make_variant grace-23h)
perl -pi -e 's/Duration\.ofHours\(24\)/Duration.ofHours(23)/' "$v/$SCORE"
if expect_changed "$v/$SCORE" "$SCORE" "Duration.ofHours(23)"; then
    out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
    expect_ok "$code" "mvn test с 23 часами"
    expect_line "$out" "[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0" "всё зелёное"
    show "$(summary_lines "$out")"
fi

section "Failures и Errors: исключение по дороге — Errors"
v=$(make_variant errors)
cat >"$v/$TEST_DIR/ForgotDeadlineTest.java" <<EOF
package $PKG;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

// Вариант для checks.sh: срок забыли — исключение, которого тест не ждал. В статью не идёт.
class ForgotDeadlineTest {

    @Test
    void forgotTheDeadline() {
        int score = DeadlineScore.score(null, Instant.parse("$DEADLINE"));

        assertThat(score).isEqualTo(100);
    }
}
EOF
out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
expect_failed "$code" "mvn test с непойманным исключением"
expect_line "$out" "[ERROR] Tests run: 3, Failures: 0, Errors: 1, Skipped: 0" "Errors: 1, а не Failures"
expect_contains "$out" "IllegalArgumentException" "исключение — IllegalArgumentException"
show "$(summary_lines "$out")"

section "Шаблоны имён Surefire: Test*, *Tests, *TestCase — да; ScoreRulesCheck и *IT — молча мимо"
v=$(make_variant names)
test_class "$v" TestDeadline pass
test_class "$v" DeadlineTestCase pass
test_class "$v" ScoreRulesCheck fail
test_class "$v" DeadlineScoreIT fail
out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
expect_ok "$code" "mvn test: красные ScoreRulesCheck и DeadlineScoreIT сборку не уронили"
expect_line "$out" "[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 4 — два теста песочницы, TestDeadline, DeadlineTestCase"
expect_report "$v" "$PKG.TestDeadline" 1 "начинается на Test — запущен"
expect_report "$v" "$PKG.DeadlineTestCase" 1 "кончается на TestCase — запущен"
expect_report "$v" "$PKG.ScoreRulesCheck" 0 "ScoreRulesCheck пропущен"
expect_report "$v" "$PKG.DeadlineScoreIT" 0 "DeadlineScoreIT без своего шаблона пропущен"
expect_not_contains "$out" "ScoreRulesCheck" "ни слова о ScoreRulesCheck в журнале — молча"
show "$(summary_lines "$out")"

section "Свой список <includes> заменяет умолчания: с *Test и *IT пропадает …Tests"
v=$(make_variant includes)
# shellcheck disable=SC2016  # $1 — группа perl, а не переменная bash
perl -0pi -e 's#(\n( *)<plugins>\n)#$1$2    <plugin>\n$2        <groupId>org.apache.maven.plugins</groupId>\n$2        <artifactId>maven-surefire-plugin</artifactId>\n$2        <configuration>\n$2            <includes>\n$2                <include>**/*Test.java</include>\n$2                <include>**/*IT.java</include>\n$2            </includes>\n$2        </configuration>\n$2    </plugin>\n#' "$v/pom.xml"
if expect_changed "$v/pom.xml" pom.xml "в pom.xml шаблоны *Test и *IT"; then
    test_class "$v" DeadlineScoreIT pass
    out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
    expect_ok "$code" "mvn test со своим списком"
    expect_line "$out" "[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 2 — DeadlineScoreTest и DeadlineScoreIT"
    expect_report "$v" "$PKG.DeadlineScoreIT" 1 "*IT запущен"
    expect_report "$v" example.testy.TestyApplicationTests 0 "TestyApplicationTests пропал"
    expect_not_contains "$out" "TestyApplicationTests" "…и молча"
    show "$(summary_lines "$out")"
fi

section "Ссылки статьи открываются"
# Ссылки на hammerhall.io — английские адреса, как в статье. Пока английской страницы нет, на сайте открывается
# русская — тогда проверяется она.
http_status() { curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
for link in https://docs.junit.org/6.0.3/writing-tests/annotations.html \
    https://assertj.github.io/doc/ \
    https://maven.apache.org/surefire/maven-surefire-plugin/examples/inclusion-exclusion.html \
    https://martinfowler.com/bliki/TestPyramid.html \
    https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches \
    https://hammerhall.io/en/ledger/articles/0-before-spring \
    https://hammerhall.io/en/ledger/articles/3a-table-and-migration \
    https://hammerhall.io/en/ledger/articles/11-guard-tests; do
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
