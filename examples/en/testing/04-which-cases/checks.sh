# Английская редакция статьи 4 серии «От красного к зелёному» (en/testing/04-which-cases.md).
# Те же проверки, что у русской, со строками программы и кусками текста по-английски.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница testy — после статьи 3: ManualCheck из статьи 1, DeadlineScore — тот же, что в статье 1;
# DeadlineScoreTest статьи 4 (таблица scoreByLateness, два теста на ошибку, тест полуночи) заменил тест статьи 3;
# Attempts и AttemptsTest — новые. В mvn verify он уже прошёл. Здесь — то, что статья обещает словами: куски кода
# в тексте — из «Пример целиком»; итог «Tests run: 18» (12 + 5 + тест start.spring.io); имена запусков —
# «late by "PT20M" → "50"», с кавычками JUnit 6 и у числа; поломки M1, M2, M5, M4 и «упрощение» коллеги
# из статьи 3 — кто красный среди тестов статей 2, 3 и 4 (таблица части 3); в журнале Maven красная строка
# названа методом с номером запуска [7]; исключение проверено по типу и тексту; сдвинутые """, опечатка PT20,
# List.of с null, «первая сдача вместо лучшей»; ссылки открываются.
# Поломки гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в статье 12: он показывает
# имена запусков так же, как IDE.

PKG=example.testy.score
CLS=$PKG.DeadlineScoreTest
SCORE=src/main/java/example/testy/score/DeadlineScore.java
ATTEMPTS=src/main/java/example/testy/score/Attempts.java
TEST_DIR=src/test/java/example/testy/score
TEST=$TEST_DIR/DeadlineScoreTest.java
ATTEMPTS_TEST=$TEST_DIR/AttemptsTest.java
ARTICLE=${ROOT:-}/en/testing/04-which-cases.md
ARTICLE1=${ROOT:-}/en/testing/01-why-tests.md
ARTICLE2=${ROOT:-}/en/testing/02-first-test.md
ARTICLE3=${ROOT:-}/en/testing/03-red-test.md
HERE=$PWD
FULL_HEAD='// src/test/java/example/testy/score/DeadlineScoreTest.java'
BUGGY_HEAD='// src/main/java/example/testy/score/DeadlineScore.java — version after the "simplification"'
M2_LINE='    static final Duration GRACE = Duration.ofHours(23);         // how late you can be and still get half'
M5_LINE='        if (submittedAt.isBefore(deadline.plus(GRACE))) {       // exactly a day late is still half'
COMMENT_ROW='# complaint from Article 3: submitted 20 minutes late, got 100'
row() { printf 'late by "%s" → "%s"' "$1" "$2"; }   # имя запуска таблицы, как в статье

# Строка вывода целиком, как в статье; пробелы в конце строки не в счёт. Аргументы: вывод, строка, пояснение.
# grep без -q: читает вывод до конца, и sed в конвейере не падает по SIGPIPE (run_examples.sh — с pipefail).
expect_line() {
    if sed 's/[[:space:]]*$//' <<<"$1" | grep -xF -- "$2" >/dev/null; then pass "$3"; else fail "$3: нет строки «$2»"; fi
}

# Итог «Tests run: …» из раздела Results и строка BUILD — для сводки. Аргумент: вывод mvn.
summary_lines() { grep -E '^\[(INFO|ERROR)\] (Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+ *$|BUILD )' <<<"$1"; }

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

# Правка варианта должна лечь. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    pass "в варианте: $3"
}

# Блок кода статьи, который начинается с этой строки. Аргументы: файл статьи, первая строка блока,
# all — первый такой во всём тексте, full — первый в «The full example».
block_from() {
    awk -v first="$2" -v where="$3" 'where == "full" && /^## The full example/ { on = 1; next }
        where == "full" && !on { next }
        /^```/ && !inside { inside = 1; buf = ""; n = 0; next }
        inside && /^```$/ { inside = 0; if (keep) { printf "%s", buf; exit } next }
        inside { if (n == 0) keep = ($0 == first); buf = buf $0 "\n"; n++ }' "$1"
}

# Куски java из текста статьи до «The full example» — по файлу на кусок: 1.txt, 2.txt… Аргумент: папка.
text_blocks() {
    awk -v dir="$1" '/^## The full example/ { exit }
        /^```java$/ { inside = 1; n++; next }
        inside && /^```$/ { inside = 0; next }
        inside { print > (dir "/" n ".txt") }' "$ARTICLE"
}

# Тест другой статьи в варианте — под своим именем класса. Аргументы: папка варианта, файл статьи, имя класса.
put_article_test() {
    block_from "$2" "$FULL_HEAD" full | sed "s/^class DeadlineScoreTest {/class $3 {/" >"$1/$TEST_DIR/$3.java"
}

# Число из итога ConsoleLauncher: «[  3 tests failed ]». Аргументы: вывод, что считать.
summary_of() { sed -nE "s/^\[ *([0-9]+) $2 .*/\1/p" <<<"$1" | head -n 1; }

# Итог ConsoleLauncher: сколько тестов упало (и ни одного контейнера). Аргументы: вывод, сколько, пояснение.
expect_failed_count() {
    local tests containers
    tests=$(summary_of "$1" 'tests failed')
    containers=$(summary_of "$1" 'containers failed')
    if [ "$tests" = "$2" ] && [ "$containers" = "0" ]; then
        pass "$3: красных $2"
    else
        fail "$3: красных ${tests:-?}, упавших контейнеров ${containers:-?}, ждали $2 и 0"
    fi
}

# Красные строки дерева. Аргумент: вывод ConsoleLauncher.
red_lines() { grep -F '✘' <<<"$1"; }

# Красные строки с первыми строками сообщения — для сводки. Аргумент: вывод ConsoleLauncher.
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 24; }

# Строка дерева красная / зелёная. Аргументы: вывод, имя в дереве, пояснение.
expect_red() {
    if red_lines "$1" | grep -F -- "$2" >/dev/null; then pass "$3"; else fail "$3: «$2» не красный"; fi
}
expect_green() { if grep -F -- "$2 ✔" <<<"$1" >/dev/null; then pass "$3"; else fail "$3: «$2» не зелёный"; fi; }

# Собрать DeadlineScore, Attempts и тесты пакета score варианта в $1/classes — без Spring.
compile_score() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$SCORE" "$1/$ATTEMPTS" "$1/$TEST_DIR"/*.java >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): пакет score не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# Классы ConsoleLauncher: дерево с именами запусков. Аргументы: путь к классам, простые имена классов.
tree_run() {
    local cp=$1 args=() c
    shift
    for c in "$@"; do args+=(--select-class "$PKG.$c"); done
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$cp:$TEST_DEPS" "${args[@]}" 2>&1
}

# Вариант с поломкой: правка perl, сборка, прогон классов. Аргументы: имя, файл, правка, что правили, классы…
# Тесты статей 2 и 3 кладутся в вариант как Art2Test и Art3Test. Вывод — в $OUT, путь варианта — в $V.
OUT=""
V=""
mutate() {
    local name=$1 file=$2 edit=$3 what=$4
    shift 4
    OUT=""
    V=$(make_variant "$name")
    put_article_test "$V" "$ARTICLE2" Art2Test
    put_article_test "$V" "$ARTICLE3" Art3Test
    perl -0pi -e "$edit" "$V/$file"
    expect_changed "$V/$file" "$file" "$what" || return 1
    compile_score "$V" || return 1
    OUT=$(tree_run "$V/classes" "$@")
}

section "Код статьи: куски в тексте — из «Пример целиком», DeadlineScore — как в статье 1"
for f in "$SCORE" "$ATTEMPTS" "$TEST" "$ATTEMPTS_TEST"; do expect_file "$f"; done
if [ -e "$TEST_DIR/ErrorTest.java" ] || [ -e "$TEST_DIR/ZoneTest.java" ]; then
    fail "фрагменты статьи 3 попали в песочницу"
else
    pass "фрагментов ErrorTest и ZoneTest в песочнице нет"
fi
src=$(cat "$TEST")
n=$(grep -cE '^    @(Test|ParameterizedTest.*)$' <<<"$src")
if [ "$n" -eq 4 ]; then pass "в DeadlineScoreTest четыре метода"; else fail "методов в DeadlineScoreTest $n, ждали 4"; fi
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    one=$(block_from "$ARTICLE1" "// src/main/java/example/testy/score/DeadlineScore.java" full)
    if [ -n "$one" ] && [ "$one" = "$(cat "$SCORE")" ]; then
        pass "DeadlineScore — слово в слово из статьи 1"
    else
        fail "DeadlineScore расходится со статьёй 1"
    fi
    midnight=$(block_from "$ARTICLE3" "$FULL_HEAD" full | sed -n '/void halfAnHourAfterMoscowMidnightIsLate/,/^    }/p')
    if [ -n "$midnight" ] && [[ "$src" == *"$midnight"* ]]; then
        pass "тест полуночи — тот же, что в статье 3"
    else
        fail "тест полуночи расходится со статьёй 3"
    fi
    mkdir -p target/text && rm -f target/text/*.txt
    text_blocks target/text
    cat "$SCORE" "$ATTEMPTS" "$TEST" "$ATTEMPTS_TEST" >target/text/full.java
    k=0 mutants=0
    while [ -f "target/text/$((k + 1)).txt" ]; do
        k=$((k + 1))
        chunk=$(cat "target/text/$k.txt")
        if [ "$chunk" = "$M2_LINE" ] || [ "$chunk" = "$M5_LINE" ]; then mutants=$((mutants + 1)); continue; fi
        missing=$(grep -v -e '^$' <<<"$chunk" | grep -vxF -f target/text/full.java)
        if [ -z "$missing" ]; then pass "кусок $k в тексте — строки из «Пример целиком»"
        else fail "кусок $k: этих строк нет в «Пример целиком»"; show "$missing"; fi
    done
    if [ "$k" -ge 9 ] && [ "$mutants" -eq 2 ]; then pass "кусков java в тексте $k, из них две строки поломок M2 и M5"
    else fail "кусков java в тексте $k, строк поломок $mutants — ждали не меньше 9 и 2"; fi
fi

section "Итог Maven: 18 тестов — 12 запусков DeadlineScoreTest, 5 AttemptsTest и тест start.spring.io"
out=$(mvn -B -ntp test 2>&1); code=$?
expect_ok "$code" "mvn test"
expect_line "$out" "[INFO] Tests run: 18, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 18, всё зелёное"
suite_ok "$CLS" 12
suite_ok "$PKG.AttemptsTest" 5
suite_ok example.testy.TestyApplicationTests 1
show "$(summary_lines "$out")"

mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp-test.txt -Dmdep.includeScope=test >/dev/null
TEST_DEPS=$(cat target/cp-test.txt)
JUNIT=$(tr ':' '\n' <<<"$TEST_DEPS" | sed -nE 's#.*/junit-jupiter-api-([0-9][0-9A-Za-z.-]*)\.jar$#\1#p' | head -n 1)
note "JUnit из BOM Boot: ${JUNIT:-не нашёлся}; $(java -version 2>&1 | head -n 1)"
rm -rf target/console
out=$(mvn -B -q -ntp dependency:copy \
    -Dartifact="org.junit.platform:junit-platform-console-standalone:$JUNIT" -DoutputDirectory=target/console 2>&1)
expect_ok $? "ConsoleLauncher JUnit $JUNIT скачан"
CONSOLE=$HERE/target/console/junit-platform-console-standalone-$JUNIT.jar
[ -f "$CONSOLE" ] || show "$(tail -n 20 <<<"$out")"

section "Имена запусков: девять строк таблицы, кавычки JUnit 6 — и у опоздания, и у числа"
OUT=$(tree_run "$HERE/target/test-classes:$HERE/target/classes" DeadlineScoreTest AttemptsTest)
expect_failed_count "$OUT" 0 "DeadlineScoreTest и AttemptsTest"
expect_line "$(summary_of "$OUT" 'tests successful')" 17 "зелёных 17: 12 + 5"
n=$(grep -cF 'late by "' <<<"$OUT")
if [ "$n" -eq 9 ]; then pass "под scoreByLateness девять запусков"; else fail "запусков таблицы $n, ждали 9"; fi
for pair in -P30D:100 PT0.000000001S:50 PT24H0.000000001S:0 PT20M:50; do
    expect_green "$OUT" "$(row "${pair%%:*}" "${pair#*:}")" "имя запуска: $(row "${pair%%:*}" "${pair#*:}")"
done
expect_not_contains "$OUT" "late by PT20M → 50" "имени без кавычек, как до JUnit 6, нет"
show "$(grep -F 'late by "' <<<"$OUT")"

section "M1 — isBefore у срока (статья 1): статья 2 — onDeadlineIsStillOnTime, статья 4 — строка PT0S"
if mutate m1-is-before "$SCORE" 's/if \(!submittedAt\.isAfter\(deadline\)\) \{/if (submittedAt.isBefore(deadline)) {/' \
    "if (submittedAt.isBefore(deadline))" DeadlineScoreTest AttemptsTest Art2Test Art3Test; then
    expect_failed_count "$OUT" 3 "M1: статьи 2, 3 и 4"
    expect_red "$OUT" "$(row PT0S 100)" "статья 4: красная строка PT0S"
    expect_red "$OUT" "onDeadlineIsStillOnTime()" "статьи 2 и 3: красный onDeadlineIsStillOnTime"
    show "$(red_lines "$OUT")"
fi

for m in m2 m5; do
    if [ "$m" = m2 ]; then
        what="M2 — сутки стали 23 часами"
        edit='s/^    static final Duration GRACE = Duration\.ofHours\(24\);.*$/$ENV{M2_LINE}/m'
    else
        what="M5 — isBefore у второй границы"
        edit='s/^        if \(!submittedAt\.isAfter\(deadline\.plus\(GRACE\)\)\) \{.*$/$ENV{M5_LINE}/m'
    fi
    section "$what: тесты статей 2 и 3 зелёные, в таблице красная строка PT24H"
    if M2_LINE=$M2_LINE M5_LINE=$M5_LINE mutate "$m" "$SCORE" "$edit" "$what — строка из статьи" \
        DeadlineScoreTest AttemptsTest Art2Test Art3Test; then
        expect_failed_count "$OUT" 1 "$what: из 4 + 6 + 17 тестов"
        expect_red "$OUT" "$(row PT24H 50)" "красная строка PT24H"
        expect_contains "$OUT" "expected: 50" "expected: 50"
        expect_contains "$OUT" "but was: 0" "but was: 0"
        show "$(red_detail "$OUT")"
    fi
done

section "M4 — нет срока, а балл 100: красный только noDeadlineIsAnError"
if mutate m4-no-deadline-full "$SCORE" 's/throw new IllegalArgumentException\("Deadline is not set"\);/return FULL;/' \
    "throw … «Deadline is not set» → return FULL;" DeadlineScoreTest AttemptsTest Art2Test Art3Test; then
    m4=$(block_from "$ARTICLE" "        if (deadline == null) {" all)
    if [ -n "$m4" ] && [[ "$(cat "$V/$SCORE")" == *"$m4"* ]]; then pass "в варианте — кусок M4 из текста"
    else fail "кусок M4 из текста в варианте не нашёлся"; fi
    expect_failed_count "$OUT" 1 "M4"
    expect_red "$OUT" "noDeadlineIsAnError()" "красный noDeadlineIsAnError"
    expect_contains "$OUT" "Expecting code to raise a throwable." "Expecting code to raise a throwable."
    show "$(red_detail "$OUT")"
fi

section "«Упрощение» коллеги из статьи 3: статья 2 зелёная, в статье 4 — три строки и тест полуночи"
buggy=$(block_from "$ARTICLE3" "$BUGGY_HEAD" all | sed -n '/long hoursLate/,/return NONE;/p')
# shellcheck disable=SC2016  # $ENV{BUGGY} — переменная perl, а не bash
if BUGGY="$buggy"$'\n' mutate colleague "$SCORE" \
    's/^        if \(!submittedAt\.isAfter\(deadline\)\) \{.*?^        return NONE;\n/$ENV{BUGGY}/ms' \
    "версия коллеги: Duration.between(…).toHours()" DeadlineScoreTest AttemptsTest Art2Test; then
    expect_contains "$(cat "$V/$SCORE")" "if (hoursLate <= GRACE.toHours()) {" "версия коллеги легла целиком"
    expect_failed_count "$OUT" 4 "версия коллеги: из 4 + 17 тестов"
    for pair in PT0.000000001S:50 PT20M:50 PT24H0.000000001S:0; do
        expect_red "$OUT" "$(row "${pair%%:*}" "${pair#*:}")" "красная строка ${pair%%:*}"
    done
    expect_red "$OUT" "halfAnHourAfterMoscowMidnightIsLate()" "красный тест полуночи"
    expect_green "$OUT" "$(row PT1H 50)" "строка PT1H зелёная: через час у коллеги тоже 50"
    show "$(red_lines "$OUT")"
fi

section "Тип и текст: перепутанные тексты ловит hasMessage, а не проверка «только по типу»"
# shellcheck disable=SC2016  # $1 — группа perl, а не переменная bash
if mutate swapped-messages "$SCORE" \
    's/"Deadline is not set"(.*?)"Submission time is not set"/"Submission time is not set"$1"Deadline is not set"/s' \
    "тексты двух проверок на null перепутаны" DeadlineScoreTest; then
    cat >"$V/$TEST_DIR/TypeOnlyTest.java" <<EOF
package $PKG;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThatThrownBy;

// Вариант для checks.sh: исключение проверено только по типу. В статью не идёт.
class TypeOnlyTest {

    @Test
    void noDeadlineTypeOnly() {
        assertThatThrownBy(() -> DeadlineScore.score(null, Instant.parse("2026-10-12T21:00:00Z")))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
EOF
    if compile_score "$V"; then
        OUT=$(tree_run "$V/classes" DeadlineScoreTest TypeOnlyTest)
        expect_failed_count "$OUT" 2 "тексты перепутаны: noDeadlineIsAnError и запуск noSubmissionTimeIsAnError"
        expect_red "$OUT" "noDeadlineIsAnError()" "красный noDeadlineIsAnError"
        expect_green "$OUT" "noDeadlineTypeOnly()" "тест «только по типу» зелёный"
        show "$(red_detail "$OUT")"
    fi
fi

section "Закрывающие \"\"\" на четыре пробела левее: 13 запусков, красный — комментарий"
if mutate shifted-quotes "$TEST" 's/^            """\)$/        """)/m' "закрывающие \"\"\" таблицы левее на 4 пробела" \
    DeadlineScoreTest; then
    expect_line "$(summary_of "$OUT" 'tests found')" 13 "запусков DeadlineScoreTest — 13"
    expect_failed_count "$OUT" 1 "сдвинутые \"\"\""
    expect_contains "$OUT" "Failed to convert String \"$COMMENT_ROW\" to type java.time.Duration" \
        "комментарий стал строкой данных: Failed to convert String \"# complaint from Article 3: …\""
    show "$(red_detail "$OUT")"
fi

section "Опечатка PT20 без единицы: Failed to convert, а не зелёный"
if mutate typo-pt20 "$TEST" 's/^            PT20M              \| 50$/            PT20               | 50/m' \
    "PT20M → PT20" DeadlineScoreTest; then
    expect_failed_count "$OUT" 1 "опечатка"
    expect_contains "$OUT" 'Failed to convert String "PT20" to type java.time.Duration' \
        'Failed to convert String "PT20" to type java.time.Duration'
fi

section "List.of не пускает null: тест с дырой упал бы с NullPointerException, ничего не проверив"
if mutate list-of-null "$ATTEMPTS_TEST" 's/Arrays\.asList\(DEADLINE, null\)/List.of(DEADLINE, null)/' \
    "Arrays.asList → List.of" AttemptsTest; then
    expect_failed_count "$OUT" 1 "List.of(DEADLINE, null)"
    expect_red "$OUT" "missingTimeInsideListIsAnError()" "красный missingTimeInsideListIsAnError"
    expect_contains "$OUT" "NullPointerException" "NullPointerException"
fi

section "Первая сдача вместо лучшей: ловится, только пока лучшая стоит не первой"
# shellcheck disable=SC2016  # $1 — группа perl, а не переменная bash
if mutate first-attempt "$ATTEMPTS" 's/\.max\(\)( +\/\/ the best submission)/.findFirst()$1/' \
    ".max() → .findFirst()" AttemptsTest; then
    expect_red "$OUT" "bestOfSeveralAttemptsCounts()" "List.of(late, early): красный bestOfSeveralAttemptsCounts"
    perl -pi -e 's/List\.of\(late, early\)/List.of(early, late)/' "$V/$ATTEMPTS_TEST"
    if expect_changed "$V/$ATTEMPTS_TEST" "$ATTEMPTS_TEST" "лучшая сдача — первой" && compile_score "$V"; then
        OUT=$(tree_run "$V/classes" AttemptsTest)
        expect_green "$OUT" "bestOfSeveralAttemptsCounts()" "List.of(early, late): тот же код проходит тест"
    fi
fi

section "Журнал Maven: красная строка таблицы названа методом с номером запуска — PT24H седьмая"
v=$(make_variant maven-23h)
perl -pi -e 's/Duration\.ofHours\(24\)/Duration.ofHours(23)/' "$v/$SCORE"
if expect_changed "$v/$SCORE" "$SCORE" "Duration.ofHours(23)"; then
    out=$(cd "$v" && mvn -B -ntp test -Dtest=DeadlineScoreTest 2>&1); code=$?
    expect_failed "$code" "mvn test -Dtest=DeadlineScoreTest с 23 часами"
    expect_line "$out" "[ERROR] Tests run: 12, Failures: 1, Errors: 0, Skipped: 0" "Tests run: 12, Failures: 1"
    expect_regex "$out" 'scoreByLateness.*\[7\]' "в журнале — scoreByLateness и номер запуска [7]"
    expect_line "$out" "expected: 50" "expected: 50"
    expect_line "$out" " but was: 0" " but was: 0"
    show "$(grep -E 'scoreByLateness.*\[7\]' <<<"$out" | head -n 3)"
    show "$(summary_lines "$out")"
fi

section "Ссылки статьи открываются"
# Ссылки на hammerhall.io — английские адреса, как в статье. Пока английской страницы нет, на сайте открывается
# русская — тогда проверяется она.
http_status() { curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
for link in https://docs.junit.org/6.0.3/writing-tests/parameterized-classes-and-tests.html \
    https://assertj.github.io/doc/ \
    "https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Duration.html" \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Instant.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/List.html \
    https://hammerhall.io/en/ledger/testing/1-why-tests \
    https://hammerhall.io/en/ledger/testing/3-red-test \
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
