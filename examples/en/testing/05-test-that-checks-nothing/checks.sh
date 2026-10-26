# Английская редакция статьи 5 серии «От красного к зелёному» (en/testing/05-test-that-checks-nothing.md).
# Те же проверки, что у русской, со строками программы и кусками текста по-английски.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница testy — после статьи 4, плюс плагин JaCoCo 0.8.15 (prepare-agent, report на verify) — тот кусок,
# что в статье. DeadlineScore — тот же, что в статье 1. Фрагменты «так не пишут» — EmptyTest и HollowTest —
# в песочницу не кладутся: их берут из текста статьи и кладут в варианты. В mvn verify песочница уже прошла.
# Здесь — то, что статья обещает словами: куски кода в тексте — из «Пример целиком» и тестов статей 2 и 4;
# плагин в pom.xml — кусок из статьи; итоги Maven 18, с фрагментами 23, с -Dtest — 12, 1 и 4; отчёт JaCoCo
# (jacoco.csv и страница исходника): у DeadlineScore 10 строк и 8 ветвей, 100% при всех тестах, при
# DeadlineScoreTest и при HollowTest, а прочие классы при HollowTest красные; при EmptyTest пропущены 2 строки
# из 10 и 2 ветви из 8 — красные «Submission time is not set» и return NONE, жёлтые ромбики у двух if; без clean
# отчёт складывает прогоны; порог 80/70 на одном DeadlineScore пустые тесты проходят, а 0,81 — уже нет;
# таблица мутантов M1–M5 — кто красный среди пустых, HollowTest, тестов статьи 2 и итоговых тестов статьи 4.
# Мутанты гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в статье 4.

PKG=example.testy.score
SCORE=src/main/java/example/testy/score/DeadlineScore.java
ATTEMPTS=src/main/java/example/testy/score/Attempts.java
TEST_DIR=src/test/java/example/testy/score
TEST=$TEST_DIR/DeadlineScoreTest.java
ARTICLE=${ROOT:-}/en/testing/05-test-that-checks-nothing.md
ARTICLE1=${ROOT:-}/en/testing/01-why-tests.md
ARTICLE2=${ROOT:-}/en/testing/02-first-test.md
ARTICLE4=${ROOT:-}/en/testing/04-which-cases.md
HERE=$PWD
JACOCO=target/site/jacoco
PAGE=$JACOCO/example.testy.score/DeadlineScore.java.html
FULL_HEAD='// src/test/java/example/testy/score/DeadlineScoreTest.java'
SCORE_HEAD='// src/main/java/example/testy/score/DeadlineScore.java'
EMPTY_HEAD="// fragment, for learning: DON'T write tests like this — four tests, green whatever breaks"
HOLLOW_HEAD="// fragment, for learning: DON'T write tests like this — 100% coverage and not a single check"
XML_HEAD='<!-- testy sandbox pom.xml: what Article 5 adds, inside <build><plugins> -->'
EMPTY4="noAssertion swallowsException agreesWithItself alwaysTrue"
TEXT="$VARIANTS/$(basename "$PWD")-text"    # куски статьи — вне target: mvn clean их не сотрёт
row() { printf 'late by "%s" → "%s"' "$1" "$2"; }   # имя запуска таблицы статьи 4

# Строка вывода целиком, как в статье; пробелы в конце строки не в счёт. Аргументы: вывод, строка, пояснение.
# grep без -q: читает вывод до конца, и sed в конвейере не падает по SIGPIPE (run_examples.sh — с pipefail).
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

# Правка варианта должна лечь. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    pass "в варианте: $3"
}

# Блок кода статьи, который начинается с этой строки. Аргументы: файл статьи, первая строка блока,
# all — первый такой во всём тексте, full — первый в «Пример целиком».
block_from() {
    awk -v first="$2" -v where="$3" 'where == "full" && /^## The full example/ { on = 1; next }
        where == "full" && !on { next }
        /^```/ && !inside { inside = 1; buf = ""; n = 0; next }
        inside && /^```$/ { inside = 0; if (keep) { printf "%s", buf; exit } next }
        inside { if (n == 0) keep = ($0 == first); buf = buf $0 "\n"; n++ }' "$1"
}

# Куски java из текста статьи до «Пример целиком» — по файлу на кусок: 1.txt, 2.txt… Аргумент: папка.
text_blocks() {
    awk -v dir="$1" '/^## The full example/ { exit }
        /^```java$/ { inside = 1; n++; next }
        inside && /^```$/ { inside = 0; next }
        inside { print > (dir "/" n ".txt") }' "$ARTICLE"
}

# Счётчики класса в jacoco.csv: «инструкций пропущено, ветвей пропущено, ветвей пройдено, строк пропущено,
# строк пройдено». Аргументы: папка проекта, пакет, класс.
counters() {
    awk -F, -v p="$2" -v c="$3" '$2 == p && $3 == c { print $4, $6, $7, $8, $9 }' "$1/$JACOCO/jacoco.csv" 2>/dev/null
}

# Счётчики DeadlineScore — как обещает статья. Аргументы: папка, образец («0 0 8 0 10»; * — любое число), пояснение.
expect_counters() {
    local got
    got=$(counters "$1" "$PKG" DeadlineScore)
    # shellcheck disable=SC2254  # образец — нарочно: * в нём значит «любое число»
    case "$got" in
        $2) pass "$3 — в jacoco.csv: $got" ;;
        *) fail "$3: в jacoco.csv «${got:-нет строки DeadlineScore}», ждали «$2»" ;;
    esac
}

# Строки страницы исходника DeadlineScore с этим цветом. Аргументы: папка, начало атрибута class («nc», «pc»).
colored() { grep -E "<span class=\"$2[\" ]" "$1/$PAGE" 2>/dev/null; }

# Сколько строк страницы с такой пометкой ветвей («bfc», «bpc», «bnc»). Аргументы: папка, пометка.
diamonds() { grep -cE "<span class=\"[a-z]+ $2\"" "$1/$PAGE" 2>/dev/null; }

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
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 40; }

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

# ConsoleLauncher: дерево с именами запусков. Аргументы: путь к классам, простые имена классов.
tree_run() {
    local cp=$1 args=() c
    shift
    for c in "$@"; do args+=(--select-class "$PKG.$c"); done
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$cp:$TEST_DEPS" "${args[@]}" 2>&1
}

# Вариант с фрагментами статьи: EmptyTest и HollowTest из «Пример целиком». Печатает путь.
with_fragments() {
    local v
    v=$(make_variant "$1")
    cp "$TEXT/EmptyTest.java" "$TEXT/HollowTest.java" "$v/$TEST_DIR/"
    echo "$v"
}

section "Код статьи: DeadlineScore — как в статье 1, тесты — статьи 4, фрагменты — не в песочнице"
for f in "$SCORE" "$ATTEMPTS" "$TEST" "$TEST_DIR/AttemptsTest.java"; do expect_file "$f"; done
if [ -e "$TEST_DIR/EmptyTest.java" ] || [ -e "$TEST_DIR/HollowTest.java" ]; then
    fail "фрагменты EmptyTest и HollowTest попали в песочницу"
else
    pass "фрагментов EmptyTest и HollowTest в песочнице нет — только в опытах"
fi
rm -rf "$TEXT" && mkdir -p "$TEXT/pieces"
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    one=$(block_from "$ARTICLE1" "$SCORE_HEAD" full)
    five=$(block_from "$ARTICLE" "$SCORE_HEAD" full)
    if [ -n "$one" ] && [ "$one" = "$(cat "$SCORE")" ] && [ "$five" = "$one" ]; then
        pass "DeadlineScore — слово в слово из статьи 1, и в «Пример целиком» статьи 5 он тот же"
    else
        fail "DeadlineScore расходится со статьёй 1"
    fi
    four=$(block_from "$ARTICLE4" "$FULL_HEAD" full)
    if [ -n "$four" ] && [ "$four" = "$(cat "$TEST")" ]; then
        pass "DeadlineScoreTest — итоговый тест статьи 4"
    else
        fail "DeadlineScoreTest расходится со статьёй 4"
    fi
    block_from "$ARTICLE" "$EMPTY_HEAD" full >"$TEXT/EmptyTest.java"
    block_from "$ARTICLE" "$HOLLOW_HEAD" full >"$TEXT/HollowTest.java"
    block_from "$ARTICLE2" "$FULL_HEAD" full >"$TEXT/Art2.java"
    empty=$(cat "$TEXT/EmptyTest.java")
    hollow=$(cat "$TEXT/HollowTest.java")
    expect_contains "$empty" "class EmptyTest {" "EmptyTest — фрагмент из «Пример целиком»"
    expect_contains "$hollow" "class HollowTest {" "HollowTest — фрагмент из «Пример целиком»"
    n=$(grep -c '^    @Test$' <<<"$empty")
    if [ "$n" -eq 4 ]; then pass "в EmptyTest четыре теста"; else fail "тестов в EmptyTest $n, ждали 4"; fi
    for t in $EMPTY4; do expect_contains "$empty" "    void $t() {" "в EmptyTest — $t"; done
    n=$(grep -c '^    @Test$' <<<"$hollow")
    if [ "$n" -eq 1 ]; then pass "в HollowTest один тест"; else fail "тестов в HollowTest $n, ждали 1"; fi
    if grep -E 'assert|fail\(' <<<"$hollow" >/dev/null; then fail "в HollowTest есть проверка"
    else pass "в HollowTest ни одной проверки: ни assert…, ни fail("; fi
    text_blocks "$TEXT/pieces"
    cat "$TEXT/EmptyTest.java" "$TEXT/HollowTest.java" "$TEXT/Art2.java" "$TEST" >"$TEXT/known.java"
    k=0
    while [ -f "$TEXT/pieces/$((k + 1)).txt" ]; do
        k=$((k + 1))
        missing=$(grep -v -e '^$' "$TEXT/pieces/$k.txt" | grep -vxF -f "$TEXT/known.java")
        if [ -z "$missing" ]; then pass "кусок $k в тексте — строки фрагментов или тестов статей 2 и 4"
        else fail "кусок $k: этих строк нет ни во фрагментах, ни в тестах статей 2 и 4"; show "$missing"; fi
    done
    if [ "$k" -eq 7 ]; then pass "кусков java в тексте 7: четыре пустых теста, две починки, HollowTest"
    else fail "кусков java в тексте $k, ждали 7"; fi
    xml_text=$(block_from "$ARTICLE" "$XML_HEAD" all)
    xml_full=$(block_from "$ARTICLE" "$XML_HEAD" full)
    if [ -n "$xml_text" ] && [ "$xml_text" = "$xml_full" ]; then
        pass "кусок pom.xml в части 2 и в «Пример целиком» один и тот же"
    else
        fail "кусок pom.xml в части 2 и в «Пример целиком» расходится"
    fi
    plugin=$(tail -n +2 <<<"$xml_full" | sed 's/^/            /')
    if [ -n "$xml_full" ] && [[ "$(cat pom.xml)" == *"$plugin"* ]]; then
        pass "в pom.xml песочницы — ровно кусок статьи, внутри <build><plugins>"
    else
        fail "плагин в pom.xml расходится с куском статьи"
    fi
    expect_contains "$xml_full" "<version>0.8.15</version>" "JaCoCo 0.8.15"
fi

section "./mvnw clean verify: 18 тестов, отчёт JaCoCo, у DeadlineScore 100% — 10 строк, 8 ветвей"
out=$(mvn -B -ntp clean verify 2>&1); code=$?
expect_ok "$code" "mvn clean verify"
expect_line "$out" "[INFO] Tests run: 18, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 18, всё зелёное"
show "$(summary_lines "$out")"
expect_file "$JACOCO/index.html"
expect_file "$JACOCO/example.testy.score/index.html"
expect_file "$JACOCO/example.testy.score/DeadlineScore.html"
expect_file "$PAGE"
n=$(grep -o '>Cov\.<' "$JACOCO/index.html" 2>/dev/null | wc -l)
if [ "$n" -eq 2 ]; then pass "в таблице отчёта два процента Cov.: инструкции и ветви"; else fail "столбцов Cov. — $n, ждали 2"; fi
expect_contains "$(cat "$JACOCO/index.html" 2>/dev/null)" ">Lines<" "строки — числами: столбец Lines"
expect_counters . "0 0 8 0 10" "все тесты: инструкций пропущено 0, ветвей 8 из 8, строк 10 из 10"

section "-Dtest=DeadlineScoreTest: 12 запусков — у DeadlineScore то же самое"
out=$(mvn -B -ntp clean verify -Dtest=DeadlineScoreTest 2>&1); code=$?
expect_ok "$code" "mvn clean verify -Dtest=DeadlineScoreTest"
expect_line "$out" "[INFO] Tests run: 12, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 12"
expect_counters . "0 0 8 0 10" "итоговые тесты статьи 4: 100%"

section "С фрагментами: 23 теста, всё зелёное — пустые тесты сборку не роняют"
F=$(with_fragments fragments)
out=$(cd "$F" && mvn -B -ntp clean verify 2>&1); code=$?
expect_ok "$code" "mvn clean verify с EmptyTest и HollowTest"
expect_line "$out" "[INFO] Tests run: 23, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 23, всё зелёное"
suite_ok "$F" "$PKG.EmptyTest" 4
suite_ok "$F" "$PKG.HollowTest" 1
show "$(summary_lines "$out")"

section "HollowTest: ни одной проверки — и 100% инструкций, ветвей и строк DeadlineScore"
out=$(cd "$F" && mvn -B -ntp clean verify -Dtest=HollowTest 2>&1); code=$?
expect_ok "$code" "mvn clean verify -Dtest=HollowTest"
expect_line "$out" "[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 1"
expect_counters "$F" "0 0 8 0 10" "HollowTest: пропущено 0 строк из 10, ветвей пройдено 8 из 8"
n=$(colored "$F" nc | wc -l); m=$(colored "$F" pc | wc -l); d=$(diamonds "$F" bfc)
if [ "$n" -eq 0 ] && [ "$m" -eq 0 ] && [ "$d" -eq 4 ]; then
    pass "страница исходника: ни красных, ни жёлтых строк, четыре зелёных ромбика"
else
    fail "страница исходника: красных $n, жёлтых $m, зелёных ромбиков $d — ждали 0, 0 и 4"
fi
for cls in "$PKG ManualCheck" "$PKG Attempts" "example.testy TestyApplication"; do
    # shellcheck disable=SC2086  # пакет и класс — два аргумента
    got=$(counters "$F" $cls)
    if [ -n "$got" ] && [ "${got##* }" = "0" ]; then pass "${cls#* } красный: этот тест его не трогал"
    else fail "${cls#* }: ждали ноль пройденных строк — «${got:-нет в отчёте}»"; fi
done

section "EmptyTest: пропущены 2 строки из 10, ветвей 75% — две красные строки, два жёлтых ромбика"
out=$(cd "$F" && mvn -B -ntp clean verify -Dtest=EmptyTest 2>&1); code=$?
expect_ok "$code" "mvn clean verify -Dtest=EmptyTest"
expect_line "$out" "[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0" "Tests run: 4"
expect_counters "$F" "* 2 6 2 8" "EmptyTest: строк пропущено 2 из 10, ветвей пройдено 6 из 8 — 75%"
note "инструкций у DeadlineScore пропущено и пройдено: $(awk -F, '$3 == "DeadlineScore" { print $4 " и " $5 }' \
    "$F/$JACOCO/jacoco.csv" 2>/dev/null)"
red=$(colored "$F" nc)
yellow=$(colored "$F" pc)
if [ "$(grep -c . <<<"$red")" -eq 2 ]; then pass "красных строк две"; else fail "красных строк: $(grep -c . <<<"$red")"; fi
expect_contains "$red" "Submission time is not set" "красная — throw «Submission time is not set»"
expect_contains "$red" "return NONE;" "красная — return NONE"
if [ "$(grep -c . <<<"$yellow")" -eq 2 ] && [ "$(diamonds "$F" bpc)" -eq 2 ]; then
    pass "жёлтых строк две, у обеих жёлтый ромбик"
else
    fail "жёлтых строк $(grep -c . <<<"$yellow"), жёлтых ромбиков $(diamonds "$F" bpc) — ждали 2 и 2"
fi
expect_contains "$yellow" "if (submittedAt == null) {" "жёлтый ромбик у if (submittedAt == null)"
expect_contains "$yellow" "if (!submittedAt.isAfter(deadline.plus(GRACE))) {" "жёлтый ромбик у второго if"
show "$(sed -e 's/<[^>]*>//g' -e 's/&quot;/"/g' <<<"$red"$'\n'"$yellow")"

section "⚠️ Без clean отчёт складывает прогоны: HollowTest, потом EmptyTest — снова 100%"
out=$(cd "$F" && mvn -B -ntp verify -Dtest=HollowTest 2>&1); code=$?
expect_ok "$code" "mvn verify -Dtest=HollowTest без clean"
out=$(cd "$F" && mvn -B -ntp verify -Dtest=EmptyTest 2>&1); code=$?
expect_ok "$code" "mvn verify -Dtest=EmptyTest без clean"
expect_line "$out" "[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0" "запущен только EmptyTest"
expect_counters "$F" "0 0 8 0 10" "а в отчёте — 0 пропущенных строк: прошлые прогоны дописаны"

section "Порог 80/70 на одном DeadlineScore: пустые тесты проходят ровно на 0,80, а 0,81 — уже нет"
T=$(with_fragments threshold)
CHECK='                    <execution>
                        <id>check</id>
                        <goals>
                            <goal>check</goal>
                        </goals>
                        <configuration>
                            <rules>
                                <rule>
                                    <element>CLASS</element>
                                    <includes>
                                        <include>example.testy.score.DeadlineScore</include>
                                    </includes>
                                    <limits>
                                        <limit>
                                            <counter>LINE</counter>
                                            <value>COVEREDRATIO</value>
                                            <minimum>0.80</minimum>
                                        </limit>
                                        <limit>
                                            <counter>BRANCH</counter>
                                            <value>COVEREDRATIO</value>
                                            <minimum>0.70</minimum>
                                        </limit>
                                    </limits>
                                </rule>
                            </rules>
                        </configuration>
                    </execution>
'
# shellcheck disable=SC2016  # $ENV{CHECK} и $1 — perl, а не bash
CHECK=$CHECK perl -0pi -e 's/^(                <\/executions>)$/$ENV{CHECK}$1/m' "$T/pom.xml"
if expect_changed "$T/pom.xml" pom.xml "работа check: LINE 0.80, BRANCH 0.70 — только DeadlineScore"; then
    out=$(cd "$T" && mvn -B -ntp clean verify -Dtest=EmptyTest 2>&1); code=$?
    expect_ok "$code" "EmptyTest, порог 80/70"
    expect_contains "$out" "All coverage checks have been met." "порог пройден: 8 из 10 строк — ровно 0,80"
    perl -pi -e 's/<minimum>0\.80<\/minimum>/<minimum>0.81<\/minimum>/' "$T/pom.xml"
    out=$(cd "$T" && mvn -B -ntp clean verify -Dtest=EmptyTest 2>&1); code=$?
    expect_failed "$code" "EmptyTest, порог строк 0,81"
    expect_contains "$out" "Rule violated for class example.testy.score.DeadlineScore" "JaCoCo называет класс"
    expect_contains "$out" "lines covered ratio" "…и счётчик строк"
    show "$(grep -E 'Rule violated|coverage checks' <<<"$out")"
fi

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

# Мутант: вариант с фрагментами и тестами статьи 2 (Art2Test), правка DeadlineScore, сборка, прогон пяти классов.
# Аргументы: M1…M5, perl-правка, что правили. Вывод — в $OUT.
OUT=""
mutate() {
    local v
    OUT=""
    v=$(with_fragments "$(tr 'M' 'm' <<<"$1")")
    sed 's/^class DeadlineScoreTest {/class Art2Test {/' "$TEXT/Art2.java" >"$v/$TEST_DIR/Art2Test.java"
    perl -0pi -e "$2" "$v/$SCORE"
    expect_changed "$v/$SCORE" "$SCORE" "$1: $3" || return 1
    compile_score "$v" || return 1
    OUT=$(tree_run "$v/classes" EmptyTest HollowTest Art2Test DeadlineScoreTest AttemptsTest)
}

# Таблица мутантов статьи: строка мутанта, его красные — в дереве и в строке таблицы, пустые и HollowTest зелёные.
# Аргументы: M1…M5, сколько красных, затем пары «имя в дереве|как в таблице».
expect_mutant() {
    local m=$1 n=$2 line pair t
    shift 2
    line=$(grep -F "| $m |" "$ARTICLE")
    expect_contains "$line" "| green | green |" "$m в таблице: 4 «пустых» зелёные, HollowTest зелёный"
    expect_failed_count "$OUT" "$n" "$m: из 4 + 1 + 4 + 17 тестов"
    for t in $EMPTY4 touchesEveryLine; do expect_green "$OUT" "$t()" "$m: $t зелёный"; done
    for pair in "$@"; do
        expect_red "$OUT" "${pair%%|*}" "$m: красный ${pair%%|*}"
        expect_contains "$line" "${pair#*|}" "$m в таблице: ${pair#*|}"
    done
    show "$(red_lines "$OUT")"
}

section "M1 — !isAfter(deadline) → isBefore(deadline): красные onDeadlineIsStillOnTime и строка PT0S"
if mutate M1 's/if \(!submittedAt\.isAfter\(deadline\)\) \{/if (submittedAt.isBefore(deadline)) {/' \
    "if (submittedAt.isBefore(deadline))"; then
    expect_mutant M1 2 "onDeadlineIsStillOnTime()|\`onDeadlineIsStillOnTime\`" "$(row PT0S 100)|\`PT0S\`"
fi

section "M2 — GRACE 24 часа → 23: тесты статьи 2 зелёные, красная строка PT24H"
if mutate M2 's/Duration\.ofHours\(24\)/Duration.ofHours(23)/' "Duration.ofHours(23)"; then
    expect_mutant M2 1 "$(row PT24H 50)|\`PT24H\`"
fi

section "M3 — во второй ветви HALF → FULL: lateWithinDayGetsHalf и шесть проверок статьи 4"
if mutate M3 's/return HALF;/return FULL;/' "return FULL; во второй ветви"; then
    expect_mutant M3 7 "lateWithinDayGetsHalf()|\`lateWithinDayGetsHalf\`" \
        "$(row PT0.000000001S 50)|\`PT0.000000001S\`" "$(row PT20M 50)|\`PT20M\`" "$(row PT1H 50)|\`PT1H\`" \
        "$(row PT24H 50)|\`PT24H\`" "halfAnHourAfterMoscowMidnightIsLate()|the midnight test" \
        "singleAttemptCountsAsIs()|\`singleAttemptCountsAsIs\` from \`AttemptsTest\`"
    expect_contains "$(grep -F -A 3 'singleAttemptCountsAsIs() ✘' <<<"$OUT")" "but was: 100" \
        "опоздавшему на три часа Attempts.best даёт 100"
fi

section "M4 — нет срока, а балл 100: красный только noDeadlineIsAnError"
if mutate M4 's/throw new IllegalArgumentException\("Deadline is not set"\);/return FULL;/' \
    "throw … «Deadline is not set» → return FULL;"; then
    expect_mutant M4 1 "noDeadlineIsAnError()|\`noDeadlineIsAnError\`"
fi

section "M5 — isBefore у второй границы: тесты статьи 2 зелёные, красная строка PT24H"
if mutate M5 's/if \(!submittedAt\.isAfter\(deadline\.plus\(GRACE\)\)\) \{/if (submittedAt.isBefore(deadline.plus(GRACE))) {/' \
    "if (submittedAt.isBefore(deadline.plus(GRACE)))"; then
    expect_mutant M5 1 "$(row PT24H 50)|\`PT24H\`"
fi

section "Ссылки статьи открываются"
# Ссылки на hammerhall.io — английские адреса, как в статье. Пока английской страницы нет, на сайте открывается
# русская — тогда проверяется она.
http_status() { curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
for link in https://www.jacoco.org/jacoco/trunk/doc/counters.html \
    https://www.jacoco.org/jacoco/trunk/doc/maven.html \
    https://www.jacoco.org/jacoco/trunk/doc/check-mojo.html \
    https://pitest.org/ \
    https://hammerhall.io/en/ledger/testing/1-why-tests \
    https://hammerhall.io/en/ledger/testing/4-which-cases \
    https://hammerhall.io/en/ledger/articles/0-before-spring \
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
