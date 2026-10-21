# Статья 11 «Тесты-сторожа» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 10: журнал в example.gameday.journal (18 файлов), миграции V1 и V2, тест периметра.
# Код статьи — чистая Java + JUnit: GameDayRules и GameDayRulesTest в src/test/java/example/gameday/journal.
# В mvn verify он уже прошёл. Здесь — лист сборки статьи: импорты и List<Arguments> с throws (класс
# собрался и прошёл: 43 запуска), подпись Named в дереве запусков, ноль запусков — красный, «строка 39»
# у IncidentLog статьи 10. И то, что статья обещает словами: рабочая папка, обход от корня находит
# миграции дважды, Path.endsWith, выражения статьи без удвоенных косых, границы правила, javac и косые,
# отрицательный контроль через ./mvnw test -Dtest=GameDayRulesTest (здесь mvn), сообщения, мутации
# сторожа — каждая валит свою строку таблицы, JaCoCo не видит src/test. Пути на Windows CI не проверит.
# Варианты гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot: он печатает дерево запусков
# с подписями — как IDE; отрицательный контроль и JaCoCo — настоящим mvn.

CLS=example.gameday.journal.GameDayRulesTest
JOURNAL=src/main/java/example/gameday/journal
LOG=$JOURNAL/IncidentLog.java
V1=src/main/resources/db/migration/V1__game_day_incident.sql
RULES=src/test/java/example/gameday/journal/GameDayRules.java
RULES_TEST=src/test/java/example/gameday/journal/GameDayRulesTest.java
REPORT=target/surefire-reports/TEST-$CLS.xml
HERE=$PWD
JACOCO=0.8.15
LINE39='строка 39: Instant.now — «сейчас» в журнале берут из часов: clock.instant()'
LINE46='строка 46: Instant.now — «сейчас» в журнале берут из часов: clock.instant()'
LINE61='строка 61: Instant.now — «сейчас» в журнале берут из часов: clock.instant()'
LINE6='строка 6: TIMESTAMP — пиши TIMESTAMPTZ (короткая форма); в Java это Instant'
MAVEN_UTF8="${MAVEN_OPTS:-} -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"

# Выражения — как статья читает их «без удвоенных косых».
INSTANT_RE=$(cat <<'EOF'
\bInstant\s*(?:\.|::)\s*now\b(?!\s*\(\s*\w)
EOF
)
NOT_CODE_RE=$(cat <<'EOF'
"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])'|//[^\n]*|/\*[\s\S]*?\*/
EOF
)

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

# Сколько строк текста подходят под выражение. Аргументы: текст, выражение.
count_lines() { LC_ALL=C.UTF-8 grep -cE -- "$2" <<<"$1"; }

# Число из итога ConsoleLauncher: «[  43 tests successful ]». Аргументы: вывод, что считать.
summary_of() { sed -nE "s/^\[ *([0-9]+) $2 .*/\1/p" <<<"$1" | head -n 1; }

# Итог прогона ConsoleLauncher. Аргументы: вывод, сколько упало тестов, сколько контейнеров, пояснение.
expect_summary() {
    local tests containers
    tests=$(summary_of "$1" 'tests failed')
    containers=$(summary_of "$1" 'containers failed')
    if [ "$tests" = "$2" ] && [ "$containers" = "$3" ]; then
        pass "$4: упало тестов $2, контейнеров $3"
    else
        fail "$4: упало тестов ${tests:-?}, контейнеров ${containers:-?}, ждали $2 и $3"
    fi
}

# Красные строки дерева: подпись и ✘. Аргумент: вывод ConsoleLauncher.
red_lines() { grep -F '✘' <<<"$1"; }

# Красная строка с этой подписью есть. Аргументы: вывод, кусок подписи, пояснение.
expect_red() {
    if red_lines "$1" | grep -qF -- "$2"; then pass "$3"; else fail "$3: нет красной строки с «$2»"; fi
}

# Строка дерева «─ подпись ✘ текст» — как в схеме статьи. Аргументы: вывод, подпись, текст, пояснение.
expect_red_line() {
    if red_lines "$1" | grep -F -- "─ $2 ✘" | grep -qF -- "$3"; then
        pass "$4"
    else
        fail "$4: нет строки «$2 ✘ $3»"
    fi
}

# GameDayRulesTest в ConsoleLauncher: рабочая папка — $1, классы тестов — $2 (по умолчанию — из mvn verify).
guards() {
    local dir=$1 classes=${2:-$HERE/target/test-classes}
    (cd "$dir" && java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$classes:$HERE/target/classes:$TEST_DEPS" \
        --select-class "$CLS" 2>&1)
}

# Собрать GameDayRules и GameDayRulesTest варианта в $1/test-classes. Код 1 — не собрались.
compile_rules() {
    rm -rf "$1/test-classes" && mkdir -p "$1/test-classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/test-classes" -cp "$HERE/target/classes:$TEST_DEPS" \
        "$1/$RULES" "$1/$RULES_TEST" >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): GameDayRules не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# Правка варианта должна что-то поменять. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    return 0
}

# Мутация сторожа: правка GameDayRules варианта, прогон, какие строки покраснели.
# Аргументы: имя, perl-правка, пояснение, сколько тестов упадёт, сколько контейнеров, куски красных подписей…
mutant() {
    local name=$1 edit=$2 what=$3 tests=$4 containers=$5 v out piece
    shift 5
    v=$(make_variant "$name")
    perl -pi -e "$edit" "$v/$RULES"
    expect_changed "$v/$RULES" "$RULES" "$what" || return 0
    compile_rules "$v" || return 0
    pass "$what — компилятор промолчал"
    out=$(guards "$v" "$v/test-classes"); code=$?
    expect_failed "$code" "$what"
    expect_summary "$out" "$tests" "$containers" "$what"
    for piece in "$@"; do
        expect_red "$out" "$piece" "…красная: $piece"
    done
    show "$(red_lines "$out")"
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CLS" 43
head=$(grep -m 1 '<testsuite' "$REPORT" 2>/dev/null)
note "импорты Arguments.arguments, Named.named, TempDir, MethodSource, ValueSource и AssertJ fail собрались; \
источники List<Arguments> с throws IOException отдали данные: ${head:-отчёта нет}"
for cls in IncidentLogTest IncidentMetricsTest IncidentTest IncidentLogIT IncidentTableIT IncidentRepositoryIT; do
    suite_green "example.gameday.journal.$cls"
done
suite_green example.gameday.PerimeterTest "тест периметра из статьи 5 — тоже сторож"
suite_green example.gameday.GameDayApplicationTests

mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp-test.txt -Dmdep.includeScope=test >/dev/null
TEST_DEPS=$(cat target/cp-test.txt)
JUNIT=$(tr ':' '\n' <<<"$TEST_DEPS" | sed -nE 's#.*/junit-jupiter-api-([0-9][0-9A-Za-z.-]*)\.jar$#\1#p' | head -n 1)
note "JUnit из BOM Boot: ${JUNIT:-не нашёлся}; $(java -version 2>&1 | head -n 1)"
expect_regex "$JUNIT" '^6\.' "JUnit 6 — как в статье (allowZeroInvocations по умолчанию false)"
rm -rf target/console
out=$(mvn -B -q -ntp dependency:copy \
    -Dartifact="org.junit.platform:junit-platform-console-standalone:$JUNIT" -DoutputDirectory=target/console 2>&1)
expect_ok $? "ConsoleLauncher JUnit $JUNIT скачан"
CONSOLE=$HERE/target/console/junit-platform-console-standalone-$JUNIT.jar
[ -f "$CONSOLE" ] || show "$(tail -n 20 <<<"$out")"

section "Дерево запусков: каждый файл — своя строка, подпись — имя файла (Named)"
out=$(guards "$HERE"); code=$?
expect_ok "$code" "ConsoleLauncher: GameDayRulesTest на песочнице"
expect_summary "$out" 0 0 "песочница после статьи 10 — сторожа зелёные"
expect_regex "$(summary_of "$out" 'tests successful')" '^43$' "зелёных запусков 43, как в «Порядке проверки»"
expect_regex "$out" '(├|└)─ timeComesFromClock\(Path\) ✔' "контейнер timeComesFromClock(Path)"
expect_regex "$out" '(├|└)─ AttackOutcome\.java ✔' "первая строка — AttackOutcome.java ✔, без папок и без кавычек"
expect_regex "$out" '(├|└)─ IncidentLog\.java ✔' "IncidentLog.java ✔ — подпись из named(…), а не путь"
expect_regex "$out" '(├|└)─ SeverityConverter\.java ✔' "последняя по алфавиту — SeverityConverter.java ✔ (порядок — в пробе ниже)"
files=$(count_lines "$out" '─ [A-Za-z]+\.java ✔')
expect_regex "$files" '^18$' "строк-файлов журнала 18 (нашлось $files)"
expect_regex "$out" '─ V1__game_day_incident\.sql ✔' "миграции — по имени файла: V1__game_day_incident.sql ✔"
expect_regex "$out" '─ V2__game_day_incident_severity\.sql ✔' "…и V2__game_day_incident_severity.sql ✔"
show "$(grep -E 'timeComesFromClock|AttackOutcome|IncidentLog\.java|SeverityConverter\.java|journalTimeHasZone|__game_day_' <<<"$out")"
show "$(grep -E 'ловит:' <<<"$out" | head -n 3)"
xml=$(grep -oE '<testcase name="[^"]*"' "$REPORT" 2>/dev/null | sed 's/<testcase name=//')
note "подписи в отчёте Surefire (target/surefire-reports): $(grep -m 3 -E 'IncidentLog|timeComesFromClock' <<<"$xml" | tr '\n' ' ')"

section "Рабочая папка, обход, Path.endsWith, выражения без удвоенных косых, границы правила"
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/GuardProbe.java" <<'EOF'
package example.gameday.journal;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

// Проба для checks.sh статьи 11: печатает то, что статья обещает словами о сторожах. В статью не идёт.
public class GuardProbe {

    public static void main(String[] args) throws Exception {
        for (String name : List.of("INSTANT_NOW", "JAVA_NOT_CODE", "SQL_COMMENT", "TIMESTAMP_WITHOUT_ZONE")) {
            Field field = GameDayRules.class.getDeclaredField(name);
            field.setAccessible(true);
            System.out.println("выражение " + name + ": " + ((Pattern) field.get(null)).pattern());
        }
        for (String code : List.of("Object t = Instant.now();", "Object t = Instant . now ( );",
                "Supplier<Instant> s = Instant::now;", "// не Instant.now(), а часы")) {
            System.out.println("contains: " + code + " → " + code.contains("Instant.now()")
                    + ", правило: " + GameDayRules.instantNowCalls(code).size());
        }
        border("текстовый блок", "String s = \"\"\"\n        Instant.now()\n        \"\"\";");
        border("import static", "import static java.time.Instant.*;\nObject t = now();");
        border("LocalDateTime.now()", "Object t = LocalDateTime.now();");
        border("System.currentTimeMillis()", "long t = System.currentTimeMillis();");
        border("Instant.now(Clock.systemUTC())", "Object t = Instant.now(Clock.systemUTC());");
        for (String sql : List.of("detected_at TIMESTAMPTZ NOT NULL", "seen_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP",
                "fixed_at TIMESTAMP(3)", "detected_at TIMESTAMP WITH TIME ZONE")) {
            System.out.println("SQL: " + sql + " → " + GameDayRules.timestampsWithoutZone(sql).size());
        }

        Path journal = Path.of("src/main/java/example/gameday/journal");
        String incident = Files.readString(journal.resolve("Incident.java"));
        Matcher dot = Pattern.compile("Instant.now").matcher(incident);
        while (dot.find()) {
            int line = 1 + (int) incident.substring(0, dot.start()).chars().filter(c -> c == '\n').count();
            System.out.println("точка без косой: Incident.java, строка " + line + ": " + dot.group());
        }
        Path file = Path.of("journal/Incident.java");
        System.out.println("Path.endsWith: на Incident.java — " + file.endsWith("Incident.java")
                + ", на .java — " + file.endsWith(".java"));
        try (Stream<Path> paths = Files.walk(journal)) {
            System.out.println("p.endsWith(\".java\") в журнале: " + paths.filter(p -> p.endsWith(".java")).count());
        }
        List<Path> files = GameDayRules.filesIn(journal, ".java");
        System.out.println("файлов журнала: " + files.size() + ", первый " + journal.relativize(files.get(0))
                + ", последний " + journal.relativize(files.get(files.size() - 1)));
        for (Path sql : GameDayRules.filesIn(Path.of("."), ".sql")) {
            if (sql.getFileName().toString().contains("__game_day_")) {
                System.out.println("от корня: " + sql);
            }
        }
        try {
            GameDayRules.filesIn(Path.of("src/main/java/example/gameday/journl"), ".java");
            System.out.println("опечатка: без исключения");
        } catch (NoSuchFileException e) {
            System.out.println("опечатка: " + e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        System.out.println("--- конец");
    }

    static void border(String what, String code) {
        System.out.println("граница: " + what + " → " + GameDayRules.instantNowCalls(code).size());
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "target/test-classes:target/classes:$TEST_DEPS" \
    "$PROBE"/src/*.java 2>&1)
expect_ok $? "javac пробы"
show "$out"
probe=$(java "${UTF8[@]}" -cp "$PROBE/classes:target/test-classes:target/classes:$TEST_DEPS" \
    example.gameday.journal.GuardProbe 2>&1)
expect_contains "$probe" "--- конец" "проба дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"
expect_line "$probe" "выражение INSTANT_NOW: $INSTANT_RE" "INSTANT_NOW без удвоенных косых — буква в букву как в статье"
expect_line "$probe" "выражение JAVA_NOT_CODE: $NOT_CODE_RE" "JAVA_NOT_CODE — четыре части статьи через |"
expect_line "$probe" 'выражение TIMESTAMP_WITHOUT_ZONE: \bTIMESTAMP\b' "TIMESTAMP_WITHOUT_ZONE — \\bTIMESTAMP\\b"
show "$(grep '^выражение' <<<"$probe")"
expect_line "$probe" "contains: Object t = Instant.now(); → true, правило: 1" "таблица contains: Instant.now() — нашёл"
expect_line "$probe" "contains: Object t = Instant . now ( ); → false, правило: 1" "…с пробелами — contains пропустил, выражение нашло"
expect_line "$probe" "contains: Supplier<Instant> s = Instant::now; → false, правило: 1" "…Instant::now — contains пропустил"
expect_line "$probe" "contains: // не Instant.now(), а часы → true, правило: 0" "…комментарий — contains нашёл зря"
expect_line "$probe" "граница: текстовый блок → 1" "текстовый блок — ложная тревога, как честно сказано"
expect_line "$probe" "граница: import static → 0" "import static с голым now() — пропуск"
expect_line "$probe" "граница: LocalDateTime.now() → 0" "LocalDateTime.now() правило не ищет"
expect_line "$probe" "граница: System.currentTimeMillis() → 0" "System.currentTimeMillis() — тоже"
expect_line "$probe" "граница: Instant.now(Clock.systemUTC()) → 0" "Instant.now(Clock.systemUTC()) пройдёт"
expect_line "$probe" "SQL: detected_at TIMESTAMPTZ NOT NULL → 0" "TIMESTAMPTZ — не нарушение"
expect_line "$probe" "SQL: seen_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP → 0" "CURRENT_TIMESTAMP — не нарушение"
expect_line "$probe" "SQL: fixed_at TIMESTAMP(3) → 1" "TIMESTAMP(3) — нарушение"
expect_line "$probe" "SQL: detected_at TIMESTAMP WITH TIME ZONE → 1" "TIMESTAMP WITH TIME ZONE — ложная тревога по договорённости"
show "$(grep -E '^(contains|граница|SQL):' <<<"$probe")"
expect_regex "$probe" '^точка без косой: Incident\.java, строка [0-9]+: Instant now$' \
    "Instant.now без \\ находит fix(Instant now) в сущности журнала"
expect_contains "$(cat "$JOURNAL/Incident.java")" "public void fix(Instant now)" "…а там — public void fix(Instant now)"
expect_line "$probe" "Path.endsWith: на Incident.java — true, на .java — false" \
    "journal/Incident.java оканчивается на Incident.java, но не на .java"
expect_line "$probe" 'p.endsWith(".java") в журнале: 0' "p.endsWith(\".java\") — ни одного файла"
expect_line "$probe" "файлов журнала: 18, первый AttackOutcome.java, последний SeverityConverter.java" \
    "рабочая папка — папка проекта: относительный путь нашёл 18 файлов; первый и последний — как в схеме"
roots=$(grep '^от корня: ' <<<"$probe")
expect_regex "$(count_lines "$roots" '^от корня: \./src/main/resources/db/migration/V[12]__game_day_')" '^2$' \
    "обход от Path.of(\".\"): миграции журнала в src/main/resources/db/migration"
expect_regex "$(count_lines "$roots" '^от корня: \./target/classes/db/migration/V[12]__game_day_')" '^2$' \
    "…и они же в target/classes/db/migration — каждая дважды"
expect_regex "$(count_lines "$roots" '^от корня: ')" '^4$' "…и больше нигде"
show "$roots"
expect_line "$probe" "опечатка: NoSuchFileException: src/main/java/example/gameday/journl" \
    "папки нет — Files.walk не прощает: NoSuchFileException"
show "$(grep -E '^(точка|Path|p\.endsWith|файлов|опечатка)' <<<"$probe")"

section "⚠️ Косые в строке Java: \"\\.\" — ошибка компиляции, \"\\b\" и \"\\s\" — молча"
ESC="$PROBE/escape"
mkdir -p "$ESC"
cat >"$ESC/Dot.java" <<'EOF'
class Dot { String re = "Instant\.now"; }
EOF
cat >"$ESC/Silent.java" <<'EOF'
class Silent { String b = "\bInstant"; String s = "Instant\s*now"; }
EOF
out=$(javac -d "$ESC" "$ESC/Dot.java" 2>&1); code=$?
expect_failed "$code" "javac: \"Instant\\.now\" в строке Java"
expect_contains "$out" "illegal escape character" "компилятор отказался: illegal escape character"
show "$(grep -v '^Picked up' <<<"$out")"
out=$(javac -d "$ESC" "$ESC/Silent.java" 2>&1)
expect_ok $? "javac: \"\\bInstant\" и \"Instant\\s*now\" — компилятор промолчал"

section "Отрицательный контроль: Instant.now() в add — mvn test -Dtest=GameDayRulesTest, строка 39"
v=$(make_variant negative-control)
perl -pi -e 's/clock\.instant\(\)/Instant.now()/ if /new Incident\(title, clock\.instant\(\)/' "$v/$LOG"
if expect_changed "$v/$LOG" "$LOG" "Instant.now() в add(title, severity)"; then
    pass "в варианте: $(grep -nF 'new Incident(title, Instant.now()' "$v/$LOG" | sed 's/^ *//')"
    out=$(cd "$v" && MAVEN_OPTS="$MAVEN_UTF8" mvn -B -ntp test -Dtest=GameDayRulesTest 2>&1); code=$?
    expect_failed "$code" "mvn test -Dtest=GameDayRulesTest"
    head=$(grep -m 1 '<testsuite' "$v/$REPORT" 2>/dev/null)
    if grep -q 'tests="43"' <<<"$head" && grep -q 'failures="1"' <<<"$head" && grep -q 'errors="0"' <<<"$head"; then
        pass "отчёт Surefire: 43 запуска, красный ровно один"
    else
        fail "отчёт Surefire: ${head:-отчёта нет}, ждали 43 и один красный"
    fi
    expect_contains "$(cat "$v/$REPORT" 2>/dev/null)" "$LINE39" "в отчёте Surefire — «$LINE39»"
    expect_contains "$out" "$LINE39" "в выводе Maven — тот же текст нарушения"
    show "$(grep -E '^\[ERROR\]' <<<"$out" | grep -E 'GameDayRulesTest|строка|Tests run' | head -n 8)"
    note "подпись упавшего запуска в отчёте Surefire: $(grep -B 1 -F '<failure' "$v/$REPORT" | grep -oE 'name="[^"]*"' | head -n 1)"
    out=$(guards "$v"); code=$?
    expect_failed "$code" "ConsoleLauncher на том же варианте"
    expect_summary "$out" 1 0 "отрицательный контроль"
    expect_red_line "$out" "IncidentLog.java" "$LINE39" "строка дерева как в схеме статьи: IncidentLog.java ✘ $LINE39"
    show "$(red_lines "$out")"
fi

section "Отрицательный контроль миграций: TIMESTAMP у detected_at в V1 — строка 6"
v=$(make_variant negative-migration)
perl -pi -e 's/TIMESTAMPTZ/TIMESTAMP/ if /^\s*detected_at\s/' "$v/$V1"
if expect_changed "$v/$V1" "$V1" "TIMESTAMP у detected_at"; then
    out=$(guards "$v"); code=$?
    expect_failed "$code" "сторож миграций"
    expect_summary "$out" 1 0 "миграция без пояса"
    expect_red_line "$out" "V1__game_day_incident.sql" "$LINE6" "V1__game_day_incident.sql ✘ $LINE6"
    show "$(red_lines "$out")"
fi

section "Все нарушения файла разом — каждое своей строкой"
v=$(make_variant all-in-one-file)
perl -pi -e 's/clock\.instant\(\)/Instant.now()/g' "$v/$LOG"
if expect_changed "$v/$LOG" "$LOG" "все clock.instant() в IncidentLog"; then
    out=$(guards "$v"); code=$?
    expect_failed "$code" "три нарушения в IncidentLog"
    expect_summary "$out" 1 0 "один файл — один красный запуск"
    expect_contains "$out" "$LINE39" "…строка 39 (add)"
    expect_line "$(sed -E 's/^[│ ]+//' <<<"$out")" "$LINE46" "…строка 46 (fixAll) — своей строкой"
    expect_line "$(sed -E 's/^[│ ]+//' <<<"$out")" "$LINE61" "…строка 61 (openLongerThan) — своей строкой"
    show "$(grep -F -A 3 'IncidentLog.java ✘' <<<"$out")"
fi

section "Сообщение: isTrue() скажет только true/false, isEmpty() напечатает список"
v=$(make_variant bare-messages)
perl -0pi -e 's/if \(!problems\.isEmpty\(\)\) \{\s*fail\(String\.join\("\\n", problems\)\);\s*\}/assertThat(problems.isEmpty()).isTrue();/' \
    "$v/$RULES_TEST"
perl -0pi -e 's/if \(!problems\.isEmpty\(\)\) \{\s*fail\(String\.join\("\\n", problems\)\);\s*\}/assertThat(problems).isEmpty();/' \
    "$v/$RULES_TEST"
perl -pi -e 's/clock\.instant\(\)/Instant.now()/ if /new Incident\(title, clock\.instant\(\)/' "$v/$LOG"
perl -pi -e 's/TIMESTAMPTZ/TIMESTAMP/ if /^\s*detected_at\s/' "$v/$V1"
expect_contains "$(cat "$v/$RULES_TEST")" "assertThat(problems.isEmpty()).isTrue();" "вариант: timeComesFromClock с isTrue()"
expect_contains "$(cat "$v/$RULES_TEST")" "assertThat(problems).isEmpty();" "вариант: journalTimeHasZone с isEmpty()"
if compile_rules "$v"; then
    out=$(guards "$v" "$v/test-classes"); code=$?
    expect_failed "$code" "оба сторожа красные"
    expect_summary "$out" 2 0 "сообщения"
    logmsg=$(grep -F -A 3 'IncidentLog.java ✘' <<<"$out")
    expect_regex "$logmsg" 'true' "isTrue(): в сообщении — true…"
    expect_regex "$logmsg" 'false' "…и false"
    expect_not_contains "$out" "строка 39" "…а где и что нашли — ни слова"
    expect_contains "$(grep -F -A 3 'V1__game_day_incident.sql ✘' <<<"$out")" "строка 6: TIMESTAMP" \
        "isEmpty(): AssertJ напечатал сам список нарушений"
    show "$logmsg"
    show "$(grep -F -A 3 'V1__game_day_incident.sql ✘' <<<"$out")"
fi

section "Как сторож врёт: каждая мутация валит свою строку таблицы"
mutant no-word-boundary 's/\\\\b/\\b/g if /bInstant/' '"\b" вместо "\\b" в INSTANT_NOW' 9 0 \
    'Object t = Instant.now();' 'java.time.Instant.now()' 'Instant . now ( );' '        .now();' \
    'Instant::now' 'http://x' 'char q = ' '/* раз */' 'findsPlantedViolator'
mutant no-s 's/\\\\s/\\s/g if /bInstant/' '"\s" вместо "\\s" в INSTANT_NOW' 1 0 '        .now();'
# shellcheck disable=SC2016  # $_ — переменная perl, а не bash
mutant no-char-part '$_ = "" if /^\s*\+ "\|\x27\(\?:/' 'без части выражения для символа' 1 0 'char q = '
mutant greedy 's/\]\*\?\\\\\*\//]*\\\\*\// if /хоть на много строк/' 'жадное * в комментарии /* */' 1 0 '/* раз */'
mutant early-slashes 's/blank\(javaSource, JAVA_NOT_CODE\)/blank(javaSource.replaceAll("\/\/[^\\\\n]*", ""), JAVA_NOT_CODE)/' \
    'сначала все // отдельной заменой' 1 0 'http://x'
mutant any-dot 's/\(\?:\\\\\.\|::\)/(?:.|::)/ if /bInstant/' 'точка без \ в (?:\.|::)' 4 0 \
    'Instant now = clock.instant();' 'fix(Instant now)' '─ Incident.java ✘' '─ IncidentLog.java ✘'
mutant sql-no-block 's/"--\[\^\\\\n\]\*\|\/\\\\\*\[\\\\s\\\\S\]\*\?\\\\\*\/"/"--[^\\\\n]*"/' \
    'SQL_COMMENT без /* */' 1 0 '/* было TIMESTAMP */'

section "Ноль файлов — красный: Path.endsWith, пустая папка, папки нет"
mutant path-endswith 's/p\.toString\(\)\.endsWith\(suffix\)/p.endsWith(suffix)/' 'p.endsWith(suffix) в filesIn' 1 2 \
    'timeComesFromClock(Path)' 'journalTimeHasZone(Path)' 'findsPlantedViolator'
v=$(make_variant empty-journal)
mkdir -p "$v/src/main/java/example/gameday/empty"
perl -pi -e 's#example/gameday/journal"#example/gameday/empty"#' "$v/$RULES_TEST"
if expect_changed "$v/$RULES_TEST" "$RULES_TEST" "JOURNAL — пустая папка" && compile_rules "$v"; then
    out=$(guards "$v" "$v/test-classes"); code=$?
    expect_failed "$code" "пустая папка: ноль запусков"
    expect_summary "$out" 0 1 "пустая папка"
    expect_red "$out" "timeComesFromClock(Path)" "красный — сам параметризованный тест: allowZeroInvocations не стоит"
    show "$(red_lines "$out")"
fi
v=$(make_variant no-such-folder)
perl -pi -e 's#example/gameday/journal"#example/gameday/journl"#' "$v/$RULES_TEST"
if expect_changed "$v/$RULES_TEST" "$RULES_TEST" "JOURNAL с опечаткой" && compile_rules "$v"; then
    out=$(guards "$v" "$v/test-classes"); code=$?
    expect_failed "$code" "папки нет"
    expect_summary "$out" 0 1 "папки нет"
    expect_red "$out" "timeComesFromClock(Path)" "красный — timeComesFromClock(Path)"
    expect_contains "$out" "NoSuchFileException" "…с NoSuchFileException"
    show "$(red_lines "$out")"
fi

section "JaCoCo меряет только src/main: сторожа в отчёте нет"
v=$(make_variant jacoco)
out=$(cd "$v" && mvn -B -ntp "org.jacoco:jacoco-maven-plugin:$JACOCO:prepare-agent" test -Dtest=GameDayRulesTest \
    "org.jacoco:jacoco-maven-plugin:$JACOCO:report" 2>&1); code=$?
expect_ok "$code" "mvn jacoco:prepare-agent test -Dtest=GameDayRulesTest jacoco:report"
csv="$v/target/site/jacoco/jacoco.csv"
if [ -f "$csv" ]; then
    expect_contains "$(cat "$csv")" ",example.gameday.journal,IncidentLog," "в отчёте — классы src/main, например IncidentLog"
    expect_not_contains "$(cat "$csv")" "GameDayRules" "GameDayRules и GameDayRulesTest в отчёте нет вовсе"
    show "$(grep -E 'IncidentLog,|GameDayRules' "$csv")"
else
    fail "отчёта JaCoCo нет"
    show "$(tail -n 20 <<<"$out")"
fi

section "Пути на Windows"
note "containsExactly(dir.resolve(\"inner/Bad.java\")) и Path.of(\"src/main/…\") на Windows CI не проверит: \
задача CI — ubuntu; на Linux findsPlantedViolator зелёный"

section "Первоисточники открываются"
for link in https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/nio/file/Files.html \
    https://docs.oracle.com/javase/tutorial/essential/exceptions/tryResourceClose.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/regex/Pattern.html \
    https://docs.junit.org/6.0.3/writing-tests/parameterized-classes-and-tests.html \
    https://docs.junit.org/6.0.3/writing-tests/built-in-extensions.html; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
