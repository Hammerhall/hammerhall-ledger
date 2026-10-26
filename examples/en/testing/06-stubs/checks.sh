# Английская редакция статьи 6 серии «От красного к зелёному» (en/testing/06-stubs.md).
# Те же проверки, что у русской, со строками программы и кусками текста по-английски.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница testy — после статьи 5; pom.xml наследуется: статья зависимостей не добавляет,
# Mockito приходит со spring-boot-starter-test. Код статьи — SubmissionLog, Deadlines, ScoreBoard, ScoreService,
# ScoreServiceTest (заглушки руками) и ScoreServiceMockitoTest в example.testy.score. В mvn verify песочница уже прошла.
# Здесь — то, что статья обещает словами: куски кода в тексте — строки «Пример целиком»; Tests run: 24, и тесты
# Mockito действительно запускаются; строки WARNING про агента — что напечатано на JDK 25 (статья говорит
# «скорее всего»); Boot 4.1 агента Mockito сам не подключает — в effective-pom нет -javaagent; поломки ScoreService
# краснеют и в тестах с заглушками руками, и в тестах Mockito; с Instant.now() красный тест выбирает календарь,
# а с Clock.fixed итог от календаря не зависит — срок в 2026 и в 2099 году; verifyNoInteractions и never()
# краснеют, если доску тронули; ArgumentCaptor видит переданное; лишний when — UnnecessaryStubbingException;
# без when для log — красный verify, без исключения; @InjectMocks — часы null; без MockitoExtension — поля null.
# Поломки гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в статьях 4 и 5.

PKG=example.testy.score
MAIN=src/main/java/example/testy/score
TEST_DIR=src/test/java/example/testy/score
SERVICE=$MAIN/ScoreService.java
HAND=$TEST_DIR/ScoreServiceTest.java
MOCK=$TEST_DIR/ScoreServiceMockitoTest.java
ARTICLE=${ROOT:-}/en/testing/06-stubs.md
BASE_POM=${ROOT:-}/examples/en/testing/05-test-that-checks-nothing/pom.xml
HERE=$PWD
H1=submittedLateWithinDayGetsHalf
H2=notSubmittedYetIsNotGraded
H3=notSubmittedAfterGraceGetsNothing
M1=lateWithinDayIsRecordedAsHalf
M2=onTimeIsRecordedAsFull
M3=earlyCheckTouchesNothing
ALL6="$H1 $H2 $H3 $M1 $M2 $M3"
TEXT="$VARIANTS/$(basename "$PWD")-text"    # куски статьи — вне target: mvn их не сотрёт

# Строка вывода целиком, как в статье; пробелы в конце строки не в счёт. Аргументы: вывод, строка, пояснение.
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

# Собрать пакет score и два класса тестов статьи в $1/classes — без Maven.
compile_score() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$MAIN"/*.java "$1/$HAND" "$1/$MOCK" >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): пакет score не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# ConsoleLauncher: оба класса тестов статьи, дерево с именами. Аргумент: путь к классам.
tree_run() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" \
        --select-class "$PKG.ScoreServiceTest" --select-class "$PKG.ScoreServiceMockitoTest" 2>&1
}

# Число из итога ConsoleLauncher: «[  3 tests failed ]». Аргументы: вывод, что считать.
summary_of() { sed -nE "s/^\[ *([0-9]+) $2 .*/\1/p" <<<"$1" | head -n 1; }

# Красные строки дерева и их сообщения — для сводки. Аргумент: вывод ConsoleLauncher.
red_detail() { grep -F -A 6 '✘' <<<"$1" | grep -v '^--$' | head -n 40; }

# Красная строка теста и сообщение под ней — до следующей строки дерева. Аргументы: вывод, имя метода.
red_of() {
    awk -v t="$2() ✘" 'index($0, t) { on = 1; print; next }
        on && (/(├─|└─)/ || /^$/ || /^Failures \(/) { exit }
        on { print }' <<<"$1"
}

# Итог варианта: сколько красных и каких; остальные из шести — зелёные. Аргументы: вывод, пояснение, красные…
expect_reds() {
    local out=$1 what=$2 t tests containers
    shift 2
    tests=$(summary_of "$out" 'tests failed')
    containers=$(summary_of "$out" 'containers failed')
    if [ "$tests" = "$#" ] && [ "$containers" = "0" ]; then
        pass "$what: красных $#"
    else
        fail "$what: красных ${tests:-?}, упавших контейнеров ${containers:-?}, ждали $# и 0"
    fi
    for t in $ALL6; do
        if [[ " $* " == *" $t "* ]]; then
            if grep -F '✘' <<<"$out" | grep -F -- "$t()" >/dev/null; then pass "$what: красный $t"
            else fail "$what: $t не красный"; fi
        elif grep -F -- "$t() ✔" <<<"$out" >/dev/null; then
            pass "$what: зелёный $t"
        else
            fail "$what: $t не зелёный"
        fi
    done
}

# Вариант: perl-правка файла, сборка, прогон обоих классов. Вывод — в $OUT, папка — в $V.
# Аргументы: имя варианта, файл, perl-правка, что правили.
OUT=""
V=""
mutate() {
    OUT=""
    V=$(make_variant "$1")
    perl -0pi -e "$3" "$V/$2"
    expect_changed "$V/$2" "$2" "$4" || return 1
    compile_score "$V" || return 1
    OUT=$(tree_run "$V/classes")
}

section "Код статьи: куски в тексте — из «Пример целиком», pom.xml — как после статьи 5"
for f in SubmissionLog Deadlines ScoreBoard ScoreService; do expect_file "$MAIN/$f.java"; done
expect_file "$HAND"
expect_file "$MOCK"
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    rm -rf "$TEXT" && mkdir -p "$TEXT"
    awk -v dir="$TEXT" '/^## The full example/ { exit }
        /^```java$/ { inside = 1; n++; next }
        inside && /^```$/ { inside = 0; next }
        inside { print > (dir "/" n ".txt") }' "$ARTICLE"
    cat "$MAIN"/SubmissionLog.java "$MAIN"/Deadlines.java "$MAIN"/ScoreBoard.java "$SERVICE" "$HAND" "$MOCK" \
        | sed 's/^[[:space:]]*//' | grep -v '^$' >"$TEXT/known.txt"
    printf '%s\n' '// … stores the neighbors in fields' \
        'verify(board, never()).record(anyString(), anyString(), anyInt());' >"$TEXT/extra.txt"
    k=0
    while [ -f "$TEXT/$((k + 1)).txt" ]; do
        k=$((k + 1))
        missing=$(sed 's/^[[:space:]]*//' "$TEXT/$k.txt" | grep -v '^$' | grep -vxF -f "$TEXT/known.txt" \
            | grep -vxF -f "$TEXT/extra.txt")
        if [ -z "$missing" ]; then pass "кусок $k в тексте — строки «Пример целиком»"
        else fail "кусок $k: этих строк нет в «Пример целиком»"; show "$missing"; fi
    done
    if [ "$k" -eq 11 ]; then pass "кусков java в тексте 11"; else fail "кусков java в тексте $k, ждали 11"; fi
fi
expect_not_contains "$(cat "$SERVICE")" "Instant.now()" "ScoreService не берёт Instant.now()…"
expect_contains "$(cat "$SERVICE")" "clock.instant()" "…«сейчас» — только из часов"
if [ -f "$BASE_POM" ] && cmp -s pom.xml "$BASE_POM"; then
    pass "pom.xml — тот же, что после статьи 5: зависимостей статья не добавляет"
else
    fail "pom.xml расходится с песочницей статьи 5"
fi

section "./mvnw test: Tests run: 24, тесты Mockito действительно запускаются"
out=$(mvn -B -ntp test 2>&1); code=$?
expect_ok "$code" "mvn test"
expect_line "$out" "[INFO] Tests run: 24, Failures: 0, Errors: 0, Skipped: 0" \
    "Tests run: 24 — 18 тестов статей 1–5 и шесть новых"
show "$(summary_lines "$out")"
suite_ok "$PKG.ScoreServiceTest" 3
suite_ok "$PKG.ScoreServiceMockitoTest" 3
for t in $M1 $M2 $M3; do
    if grep -q "testcase name=\"$t\"" "target/surefire-reports/TEST-$PKG.ScoreServiceMockitoTest.xml" 2>/dev/null; then
        pass "в отчёте Surefire — $t"
    else
        fail "в отчёте Surefire нет $t"
    fi
done

section "Строки WARNING про агента: на JDK 25 — только предупреждение; Boot 4.1 агента не подключает"
note "$(java -version 2>&1 | grep -v '^Picked up' | head -n 1)"
warn=$({ echo "$out"; cat target/surefire-reports/* 2>/dev/null; } \
    | grep -E 'Mockito is currently self-attaching|agent has been loaded dynamically|Dynamic loading of agents' \
    | sed 's/^[[:space:]]*//' | sort -u)
if [ -n "$warn" ]; then
    pass "в журнале и отчётах — строки про агента, о которых предупреждает статья; тесты при этом зелёные"
    show "$warn"
else
    note "строк про агента нет — проверь абзац «Строки WARNING в журнале»: статья говорит «скорее всего, появятся»"
fi
rm -f target/effective-pom.xml
mvn -B -q -ntp help:effective-pom -Doutput=target/effective-pom.xml >/dev/null 2>&1
if [ ! -s target/effective-pom.xml ]; then
    fail "effective-pom не собрался — не проверить, подключает ли Boot агента"
elif grep -qE -- '-javaagent|EnableDynamicAgentLoading' target/effective-pom.xml; then
    fail "в effective-pom есть -javaagent или EnableDynamicAgentLoading: сборка настроена — поправь часть 3 статьи"
    show "$(grep -nE -- '-javaagent|EnableDynamicAgentLoading' target/effective-pom.xml)"
else
    pass "в effective-pom нет ни -javaagent, ни EnableDynamicAgentLoading: Boot 4.1 и песочница агента не подключают"
fi

mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp-test.txt -Dmdep.includeScope=test >/dev/null
TEST_DEPS=$(cat target/cp-test.txt)
JUNIT=$(tr ':' '\n' <<<"$TEST_DEPS" | sed -nE 's#.*/junit-jupiter-api-([0-9][0-9A-Za-z.-]*)\.jar$#\1#p' | head -n 1)
MOCKITO=$(tr ':' '\n' <<<"$TEST_DEPS" | sed -nE 's#.*/mockito-core-([0-9][0-9A-Za-z.-]*)\.jar$#\1#p' | head -n 1)
note "из BOM Boot: JUnit ${JUNIT:-не нашёлся}, Mockito ${MOCKITO:-не нашёлся}"
rm -rf target/console
out=$(mvn -B -q -ntp dependency:copy \
    -Dartifact="org.junit.platform:junit-platform-console-standalone:$JUNIT" -DoutputDirectory=target/console 2>&1)
expect_ok $? "ConsoleLauncher JUnit $JUNIT скачан"
CONSOLE=$HERE/target/console/junit-platform-console-standalone-$JUNIT.jar
[ -f "$CONSOLE" ] || show "$(tail -n 20 <<<"$out")"

section "ConsoleLauncher: шесть тестов статьи зелёные и здесь"
V=$(make_variant as-is)
if compile_score "$V"; then
    OUT=$(tree_run "$V/classes")
    expect_reds "$OUT" "как в статье"
    expect_regex "$(summary_of "$OUT" 'tests successful')" '^6$' "зелёных 6"
fi

section "Без записи после подсчёта балла: красные и тест с заглушкой руками, и тесты Mockito"
if mutate no-record "$SERVICE" 's/^        board\.record\(studentId, taskKey, score\);\n//m' \
    "вычеркнута board.record(studentId, taskKey, score);"; then
    expect_reds "$OUT" "без записи" "$H1" "$M1" "$M2"
    expect_contains "$(red_of "$OUT" "$H1")" "student-1 T-7 50" "$H1 — на проверке доски: ждали «student-1 T-7 50»"
    expect_contains "$(red_of "$OUT" "$M1")" "Wanted but not invoked" "$M1 — вызова не было"
    expect_contains "$(red_of "$OUT" "$M2")" "Wanted but not invoked" "$M2 — вызова не было"
    show "$(red_detail "$OUT")"
fi

section "Без записи нуля в ветке «сутки прошли»: красный notSubmittedAfterGraceGetsNothing"
if mutate no-zero "$SERVICE" 's/^                board\.record\(studentId, taskKey, DeadlineScore\.NONE\);\n//m' \
    "вычеркнута board.record(studentId, taskKey, DeadlineScore.NONE);"; then
    expect_reds "$OUT" "без записи нуля" "$H3"
    expect_contains "$(red_of "$OUT" "$H3")" "student-1 T-7 0" "$H3 — ноль в ответе верный, а на доске пусто"
    show "$(red_detail "$OUT")"
fi

section "Instant.now() вместо часов: какой тест красный — решает календарь"
now=$(date -u +%s)
edge=$(date -u -d 2026-10-13T21:00:00Z +%s)
note "сейчас $(date -u +%FT%TZ); срок плюс сутки — 2026-10-13T21:00:00Z"
if mutate instant-now "$SERVICE" 's/clock\.instant\(\)/Instant.now()/' "clock.instant() → Instant.now()"; then
    if [ "$now" -gt "$edge" ]; then
        expect_reds "$OUT" "после 13.10.2026 21:00 UTC" "$H2" "$M3"
    else
        expect_reds "$OUT" "до 13.10.2026 21:00 UTC" "$H3"
    fi
    show "$(red_detail "$OUT")"
fi

section "Clock.fixed: срок в 2099 году — те же шесть зелёных; с Instant.now() красный другой тест"
V=$(make_variant year-2099)
perl -pi -e 's/2026-10-12T21:00:00Z/2099-10-12T21:00:00Z/g' "$V/$HAND" "$V/$MOCK"
if expect_changed "$V/$HAND" "$HAND" "DEADLINE в ScoreServiceTest — 2099-10-12T21:00:00Z" \
    && expect_changed "$V/$MOCK" "$MOCK" "DEADLINE в ScoreServiceMockitoTest — 2099-10-12T21:00:00Z" \
    && compile_score "$V"; then
    OUT=$(tree_run "$V/classes")
    expect_reds "$OUT" "срок в 2099, часы Clock.fixed"
    perl -pi -e 's/clock\.instant\(\)/Instant.now()/' "$V/$SERVICE"
    if expect_changed "$V/$SERVICE" "$SERVICE" "срок в 2099 и Instant.now()" && compile_score "$V"; then
        OUT=$(tree_run "$V/classes")
        expect_reds "$OUT" "срок в 2099, Instant.now(): настоящие сутки ещё не прошли" "$H3"
        show "$(red_detail "$OUT")"
    fi
fi

section "verifyNoInteractions краснеет, если доску тронули; never() — так же"
NEVER=$(grep -m 1 '^verify(board, never())' "$ARTICLE" 2>/dev/null)
export NEVER
expect_contains "$NEVER" "verify(board, never()).record(" "строка с never() — из текста статьи"
# shellcheck disable=SC2016  # $1 — группа perl, а не переменная bash
if mutate touch-board "$SERVICE" 's/^(            return Optional\.empty\(\);)/            board.record(studentId, taskKey, DeadlineScore.NONE);\n$1/m' \
    "«ещё не поздно», а на доску пишут ноль"; then
    expect_reds "$OUT" "доску тронули" "$H2" "$M3"
    expect_contains "$(red_of "$OUT" "$H2")" "student-1 T-7 0" "$H2 — на доске ноль, а ждали пусто"
    expect_contains "$(red_of "$OUT" "$M3")" "No interactions wanted here" "$M3 — verifyNoInteractions: с доской что-то делали"
    show "$(red_detail "$OUT")"
    touched=$V
    # shellcheck disable=SC2016  # $ENV{NEVER} и $1 — perl, а не bash
    if [ -n "$NEVER" ] && mutate never "$MOCK" \
        's/^        verifyNoInteractions\(board\);.*$/        $ENV{NEVER}/m; s/^(import static org\.mockito\.Mockito\.when;)$/import static org.mockito.ArgumentMatchers.anyInt;\nimport static org.mockito.Mockito.never;\n$1/m' \
        "verifyNoInteractions(board) → строка never() из статьи"; then
        expect_reds "$OUT" "never() на верной службе"
        cp "$touched/$SERVICE" "$V/$SERVICE"
        if compile_score "$V"; then
            OUT=$(tree_run "$V/classes")
            expect_reds "$OUT" "never(), доску тронули" "$H2" "$M3"
            expect_contains "$(red_of "$OUT" "$M3")" "Never wanted here" "$M3 — never(): вызов record был"
        fi
    fi
fi

section "ArgumentCaptor видит переданное: на доску пишут 50 вместо балла"
if mutate half-recorded "$SERVICE" \
    's/board\.record\(studentId, taskKey, score\);/board.record(studentId, taskKey, DeadlineScore.HALF);/' \
    "board.record(…, DeadlineScore.HALF) вместо score"; then
    expect_reds "$OUT" "пишут 50" "$M2"
    detail=$(red_of "$OUT" "$M2")
    expect_contains "$detail" "expected: 100" "перехватчик: ждали 100…"
    expect_contains "$detail" "but was: 50" "…а служба передала 50"
    show "$(red_detail "$OUT")"
fi

section "Строгие заглушки: лишний when для «student-2» — UnnecessaryStubbingException"
# shellcheck disable=SC2016  # $1 — группа perl, а не переменная bash
if mutate extra-when "$MOCK" \
    's/^(        when\(log\.submittedAt\("student-1", "T-7"\)\)\.thenReturn\(Optional\.of\(DEADLINE\.plus\(Duration\.ofHours\(2\)\)\)\);\n)/$1        when(log.submittedAt("student-2", "T-7")).thenReturn(Optional.empty());\n/m' \
    "в $M1 лишний when для «student-2»"; then
    expect_reds "$OUT" "лишний when" "$M1"
    expect_contains "$OUT" "UnnecessaryStubbingException" "тест упал с UnnecessaryStubbingException — проверка при этом сошлась"
    expect_not_contains "$OUT" "PotentialStubbingProblem" "…а не с PotentialStubbingProblem: вызов «student-1» совпал со своей заглушкой"
    show "$(red_detail "$OUT")"
fi

section "Забыли when для log: служба молча идёт путём «не сдал», красный verify"
if mutate no-when "$MOCK" \
    's/^        when\(log\.submittedAt\("student-1", "T-7"\)\)\.thenReturn\(Optional\.of\(DEADLINE\.plus\(Duration\.ofHours\(2\)\)\)\);\n//m' \
    "в $M1 нет when для log"; then
    expect_reds "$OUT" "без when для log" "$M1"
    expect_contains "$(red_of "$OUT" "$M1")" "Argument(s) are different!" "$M1 — record позвали, но не с 50"
    expect_not_contains "$OUT" "NullPointerException" "исключения нет: пустой Optional — ответ по умолчанию"
    expect_not_contains "$OUT" "UnnecessaryStubbingException" "…и строгий режим молчит"
    show "$(red_detail "$OUT")"
fi

section "@InjectMocks вместо new: часы null — «сдал» зелёные, «не сдал» падает с NullPointerException"
# shellcheck disable=SC2016  # $1 — группа perl, а не переменная bash
if mutate inject-mocks "$MOCK" \
    's/^    private ScoreService service;$/    \@InjectMocks\n    private ScoreService service;/m; s/^        Clock fiveDaysLater = .*\n        service = new ScoreService\(log, deadlines, board, fiveDaysLater\);\n//m; s/^        Clock threeHoursLater = .*\n        service = new ScoreService\(log, deadlines, board, threeHoursLater\);\n//m; s/^(import org\.mockito\.Mock;)$/import org.mockito.InjectMocks;\n$1/m' \
    "@InjectMocks над полем service, без new ScoreService(…)"; then
    expect_not_contains "$(cat "$V/$MOCK")" "new ScoreService" "в варианте службу собирает только @InjectMocks"
    expect_reds "$OUT" "@InjectMocks" "$M3"
    expect_contains "$OUT" "NullPointerException" "$M3 — NullPointerException…"
    expect_contains "$(red_of "$OUT" "$M3")" '"this.clock" is null' "…на часах: this.clock — null"
    show "$(red_detail "$OUT")"
fi

section "Без @ExtendWith(MockitoExtension.class): поля @Mock — null, тесты падают на первом обращении"
if mutate no-extension "$MOCK" 's/^\@ExtendWith\(MockitoExtension\.class\)\n//m' "без @ExtendWith(MockitoExtension.class)"; then
    expect_reds "$OUT" "без MockitoExtension" "$M1" "$M2" "$M3"
    expect_contains "$(red_of "$OUT" "$M1")" '"this.deadlines" is null' "заглушки срока нет: this.deadlines — null"
    show "$(red_detail "$OUT")"
fi

section "Ссылки статьи открываются"
# Ссылки на hammerhall.io — английские адреса, как в статье. Пока английской страницы нет, на сайте открывается
# русская — тогда проверяется она.
http_status() { curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
for link in https://www.javadoc.io/static/org.mockito/mockito-core/5.24.0/org.mockito/org/mockito/Mockito.html \
    https://www.javadoc.io/static/org.mockito/mockito-core/5.24.0/org.mockito/org/mockito/exceptions/misusing/UnnecessaryStubbingException.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Clock.html \
    https://docs.spring.io/spring/reference/testing/annotations/integration-spring/annotation-mockitobean.html \
    https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html \
    https://hammerhall.io/en/ledger/testing/5-test-that-checks-nothing \
    https://hammerhall.io/en/ledger/articles/1-why-spring \
    https://hammerhall.io/en/ledger/articles/4-web; do
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
