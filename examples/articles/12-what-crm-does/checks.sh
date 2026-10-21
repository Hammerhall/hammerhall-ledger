# Статья 12 «Что делает CRM: следующий шаг с датой» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 11: журнал в example.gameday.journal (18 файлов), сторожа GameDayRulesTest (43 запуска).
# Код статьи — чистая Java: FollowUp и TodayList в src/main/java/example/crm, TodayListTest в src/test/java/example/crm.
# В mvn verify он уже прошёл. Здесь — то, что статья обещает словами: модель без Spring и рядом с корнем пакетов;
# у сторожа статьи 11 по-прежнему 43 запуска, модель он не видит, а «сейчас» она и так берёт из часов;
# таблица «Почему не untilAt» по МСК — на данных самого теста; понедельник, полночь по Москве, +03:00;
# порядок по dueAt и 💡 nullsLast по untilAt; «что будет, если» — мутации TodayList и FollowUp: какой тест
# краснеет и с чем (NullPointerException, Expecting actual: и []); первоисточники открываются.
# Мутации гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в статье 11.

CLS=example.crm.TodayListTest
CRM=src/main/java/example/crm
CRM_TEST=src/test/java/example/crm
FOLLOW_UP=$CRM/FollowUp.java
TODAY=$CRM/TodayList.java
TODAY_TEST=$CRM_TEST/TodayListTest.java
HERE=$PWD
T1=showsOpenTasksDueTodayAndOverdue
T2=dayEndsAtMidnightInTheClockZone
T3=taskWithoutDueDateDoesNotExist

# Таблица «Почему не untilAt» — как в статье, по МСК; первый столбец — о ком задача в тесте.
TABLE='человек-1 | RENEWAL | 02.10 12:00 | 09.10 12:00 | да
человек-4 | OFFER | 05.10 02:30 | — | да
человек-2 | RENEWAL | 05.10 09:00 | 12.10 09:00 | да
человек-5 | HOLD | 05.10 11:15 | 06.10 11:00 | да
человек-3 | RENEWAL | 08.10 03:00 | 15.10 03:00 | нет
человек-6 | RENEWAL | 05.10 09:00 | 12.10 09:00 | нет'

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

# Число из итога ConsoleLauncher: «[  3 tests successful ]». Аргументы: вывод, что считать.
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

# Красные строки дерева с первыми строками сообщения — для сводки. Аргумент: вывод ConsoleLauncher.
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 12; }

# Тест красный / зелёный в дереве. Аргументы: вывод, имя метода, пояснение.
expect_red()   { if red_lines "$1" | grep -qF -- "$2()"; then pass "$3"; else fail "$3: $2 не красный"; fi; }
expect_green() { if grep -qF -- "$2() ✔" <<<"$1"; then pass "$3"; else fail "$3: $2 не зелёный"; fi; }

# Что AssertJ показал после «Expecting actual:» — все такие куски вывода, до «to contain exactly».
actual_parts() { sed -n '/Expecting actual:/,/to contain exactly/p' <<<"$1"; }

# Правка варианта должна что-то поменять. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    return 0
}

# Собрать модель и тест варианта в $1/classes — только example.crm, без target/classes песочницы.
compile_crm() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$CRM"/*.java "$1/$CRM_TEST"/*.java >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): example.crm не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# TodayListTest в ConsoleLauncher на классах из $1.
today_test() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" --select-class "$CLS" 2>&1
}

# Мутация: правка файла варианта (perl), сборка, прогон TodayListTest. Печатает вывод в $OUT.
# Аргументы: имя варианта, файл, perl-правка, что правили, флаги perl (необязательно).
OUT=""
mutate() {
    local name=$1 file=$2 edit=$3 what=$4 flags=${5:--pi} v
    OUT=""
    v=$(make_variant "$name")
    perl "$flags" -e "$edit" "$v/$file"
    expect_changed "$v/$file" "$file" "$what" || return 1
    pass "в варианте: $what"
    compile_crm "$v" || return 1
    OUT=$(today_test "$v/classes"); code=$?
    expect_failed "$code" "$what: TodayListTest"
    MUTANT=$v
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CLS" 3
suite_ok example.gameday.journal.GameDayRulesTest 43
note "у сторожа статьи 11 по-прежнему 43 запуска: 18 файлов журнала, 2 миграции, 22 строки таблиц, временная папка"
for cls in IncidentLogTest IncidentMetricsTest IncidentTest IncidentLogIT; do
    suite_green "example.gameday.journal.$cls"
done
suite_green example.gameday.PerimeterTest "тест периметра из статьи 5"
suite_green example.gameday.GameDayApplicationTests "контекст поднялся — example.crm ему не мешает"

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

section "Модель — чистая Java рядом с корнем пакетов, Spring её не видит"
src=$(cat "$CRM"/*.java)
expect_not_contains "$src" "org.springframework" "в FollowUp и TodayList нет ни одного импорта Spring"
expect_not_contains "$src" "@Component" "…и ни одной аннотации компонента"
expect_contains "$(cat src/main/java/example/gameday/GameDayApplication.java)" "package example.gameday;" \
    "корень пакетов — example.gameday: там @SpringBootApplication"
expect_contains "$src" "package example.crm;" "модель — в example.crm: рядом с корнем, не внутри"
out=$(today_test "$HERE/target/test-classes:$HERE/target/classes"); code=$?
expect_ok "$code" "ConsoleLauncher: TodayListTest на песочнице"
expect_summary "$out" 0 0 "три теста статьи"
expect_regex "$(summary_of "$out" 'tests successful')" '^3$' "зелёных 3"
show "$(grep -E "$T1|$T2|$T3" <<<"$out")"

section "Таблица «Почему не untilAt», МСК, полночь, nullsLast — на данных самого теста; сторож статьи 11"
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/CrmProbe.java" <<'EOF'
package example.gameday.journal;

import example.crm.FollowUp;
import example.crm.TodayList;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Проба для checks.sh статьи 12: печатает то, что статья обещает словами. В статью не идёт.
// Пакет — журнала: GameDayRules статьи 11 виден только из него.
public class CrmProbe {

    static final ZoneId MSK = ZoneId.of("Europe/Moscow");
    static final DateTimeFormatter DAY_TIME = DateTimeFormatter.ofPattern("dd.MM HH:mm").withZone(MSK);

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].equals("guard")) {
            for (int i = 1; i < args.length; i++) {
                Path file = Path.of(args[i]);
                System.out.println("сторож: " + file.getFileName() + " → "
                        + GameDayRules.instantNowCalls(Files.readString(file)).size());
            }
            return;
        }
        // Задачи первого теста — прямо из TodayListTest.java (args[1]): таблица статьи сверяется с данными теста.
        String test = Files.readString(Path.of(args[1]));
        String first = test.substring(test.indexOf("void showsOpenTasksDueTodayAndOverdue"),
                test.indexOf("void dayEndsAtMidnightInTheClockZone"));
        // new FollowUp("KIND", "кто",   // комментарий
        //         Instant.parse("…"), Instant.parse("…") или null, true/false)
        Matcher m = Pattern.compile("new FollowUp\\(\"(\\w+)\", \"([^\"]+)\",\\s*(?://[^\\n]*\\s*)?"
                + "Instant\\.parse\\(\"([^\"]+)\"\\), (?:null|Instant\\.parse\\(\"([^\"]+)\"\\)), (true|false)\\)")
                .matcher(first);
        List<FollowUp> all = new ArrayList<>();
        while (m.find()) {
            all.add(new FollowUp(m.group(1), m.group(2), Instant.parse(m.group(3)),
                    m.group(4) == null ? null : Instant.parse(m.group(4)), Boolean.parseBoolean(m.group(5))));
        }
        System.out.println("задач первого теста: " + all.size());
        Clock noon = Clock.fixed(Instant.parse("2026-10-05T09:00:00Z"), MSK);
        List<FollowUp> shown = new TodayList(noon).select(all);
        for (FollowUp task : all) {
            System.out.println("строка: " + task.who() + " | " + task.kind() + " | " + DAY_TIME.format(task.dueAt())
                    + " | " + (task.untilAt() == null ? "—" : DAY_TIME.format(task.untilAt()))
                    + " | " + (shown.contains(task) ? "да" : "нет"));
        }
        System.out.println("по dueAt: " + names(shown));
        System.out.println("nullsLast по untilAt: " + names(shown.stream()
                .sorted(Comparator.comparing(FollowUp::untilAt, Comparator.nullsLast(Comparator.naturalOrder())))
                .toList()));
        System.out.println("5 октября 2026: " + LocalDate.of(2026, 10, 5).getDayOfWeek());
        System.out.println("полночь 05.10 по Москве: " + LocalDate.of(2026, 10, 5).atStartOfDay(MSK).toInstant());
        System.out.println("сдвиг Москвы: 05.10.2026 " + MSK.getRules().getOffset(Instant.parse("2026-10-05T09:00:00Z"))
                + ", 01.07.2026 " + MSK.getRules().getOffset(Instant.parse("2026-07-01T09:00:00Z")));
        for (String code : List.of("LocalDate.now()", "LocalDate.now(clock)", "Instant.now()")) {
            System.out.println("сторож на «" + code + "» → " + GameDayRules.instantNowCalls(code).size());
        }
        Path journal = Path.of("src/main/java/example/gameday/journal");
        List<Path> files = GameDayRules.filesIn(journal, ".java");
        System.out.println("сторож обходит: " + files.size() + " файлов, из example.crm — "
                + files.stream().filter(p -> p.toString().contains("crm")).count());
        System.out.println("--- конец");
    }

    static String names(List<FollowUp> tasks) {
        return String.join(", ", tasks.stream().map(t -> t.who() + " " + t.kind()).toList());
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "target/test-classes:target/classes:$TEST_DEPS" \
    "$PROBE"/src/*.java 2>&1)
expect_ok $? "javac пробы"
show "$out"
PROBE_CP="$PROBE/classes:target/test-classes:target/classes:$TEST_DEPS"
probe=$(java "${UTF8[@]}" -cp "$PROBE_CP" example.gameday.journal.CrmProbe table "$TODAY_TEST" 2>&1)
expect_contains "$probe" "--- конец" "проба дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"
expect_line "$probe" "задач первого теста: 6" "в первом тесте шесть задач — строки таблицы"
while IFS= read -r row; do
    expect_line "$probe" "строка: $row" "таблица статьи: $row"
done <<<"$TABLE"
show "$(grep '^строка:' <<<"$probe")"
expect_line "$probe" "по dueAt: человек-1 RENEWAL, человек-4 OFFER, человек-2 RENEWAL, человек-5 HOLD" \
    "список по dueAt: просроченное, предложение, продление, бронь — бронь последней"
expect_line "$probe" "nullsLast по untilAt: человек-5 HOLD, человек-1 RENEWAL, человек-2 RENEWAL, человек-4 OFFER" \
    "💡 nullsLast по untilAt: бронь первой, предложение в конце"
expect_line "$probe" "5 октября 2026: MONDAY" "5 октября 2026 — понедельник"
expect_line "$probe" "полночь 05.10 по Москве: 2026-10-04T21:00:00Z" "полночь по Москве — 21:00 по UTC накануне"
expect_line "$probe" "сдвиг Москвы: 05.10.2026 +03:00, 01.07.2026 +03:00" "у Москвы круглый год +03:00"
expect_line "$probe" "сторож на «LocalDate.now()» → 0" "⚠️ LocalDate.now() сторож статьи 11 не ищет — промолчит"
expect_line "$probe" "сторож на «Instant.now()» → 1" "…а Instant.now() ловит: сторож живой"
expect_line "$probe" "сторож обходит: 18 файлов, из example.crm — 0" "сторож смотрит только в папку журнала: 18 файлов, модели среди них нет"
show "$(grep -E '^(по dueAt|nullsLast|5 октября|полночь|сдвиг|сторож)' <<<"$probe")"
guard=$(java "${UTF8[@]}" -cp "$PROBE_CP" example.gameday.journal.CrmProbe guard "$FOLLOW_UP" "$TODAY" 2>&1)
expect_line "$guard" "сторож: FollowUp.java → 0" "правило сторожа модель держит и так: FollowUp.java"
expect_line "$guard" "сторож: TodayList.java → 0" "…и TodayList.java — «сейчас» только из часов"
show "$guard"

section "Тест, который не краснел, ничего не доказал: untilAt вместо dueAt"
if mutate until-at "$TODAY" 's/task\.dueAt\(\)\.isBefore\(tomorrow\)/task.untilAt().isBefore(tomorrow)/' \
    "task.untilAt() вместо task.dueAt() в отборе"; then
    expect_summary "$OUT" 2 0 "untilAt без проверки на null"
    expect_red "$OUT" "$T1" "первый тест красный…"
    expect_contains "$OUT" "NullPointerException" "…с NullPointerException"
    expect_contains "$OUT" 'FollowUp.untilAt()" is null' "…на предложении: untilAt() — null"
    expect_red "$OUT" "$T2" "второй тест красный…"
    expect_contains "$OUT" "Expecting actual:" "…с Expecting actual:"
    expect_regex "$(actual_parts "$OUT")" '\[\][[:space:]]*$' "…и пустым [] — список пуст"
    expect_green "$OUT" "$T3" "третий зелёный"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: та же подмена с проверкой на null"
if mutate until-at-null-check "$TODAY" \
    's/task\.dueAt\(\)\.isBefore\(tomorrow\)/task.untilAt() != null \&\& task.untilAt().isBefore(tomorrow)/' \
    "task.untilAt() != null && task.untilAt().isBefore(tomorrow)"; then
    expect_summary "$OUT" 2 0 "untilAt с проверкой на null"
    expect_red "$OUT" "$T1" "первый красный"
    expect_red "$OUT" "$T2" "второй красный"
    expect_not_contains "$OUT" "NullPointerException" "ни одной ошибки — только пустой список"
    expect_not_contains "$(actual_parts "$OUT")" "FollowUp[" "в обоих Expecting actual: — ни одной задачи"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без !task.done() — в списке висит сделанное"
# shellcheck disable=SC2016  # $_ — переменная perl, а не bash
if mutate no-done "$TODAY" '$_ = "" if /\.filter\(task -> !task\.done\(\)\)/' "без .filter(task -> !task.done())"; then
    expect_summary "$OUT" 1 0 "без !done"
    expect_red "$OUT" "$T1" "красный первый"
    expect_green "$OUT" "$T2" "второй зелёный"
    expect_contains "$(actual_parts "$OUT")" "человек-6" "в списке — закрытая задача человек-6"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: «строго сегодня» — просроченное пропало"
if mutate strictly-today "$TODAY" \
    's/\.filter\(task -> task\.dueAt\(\)\.isBefore\(tomorrow\)\)/.filter(task -> !task.dueAt().isBefore(tomorrow.minusSeconds(86_400)) \&\& task.dueAt().isBefore(tomorrow))/' \
    "dueAt от полуночи до полуночи"; then
    expect_summary "$OUT" 1 0 "строго сегодня"
    expect_red "$OUT" "$T1" "красный первый"
    expect_green "$OUT" "$T2" "второй зелёный"
    parts=$(actual_parts "$OUT")
    expect_not_contains "$(sed '/to contain exactly/d' <<<"$parts")" "человек-1" "в списке нет просроченного человек-1"
    expect_contains "$parts" "человек-4" "…а предложение человек-4 есть"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: полночь по UTC вместо пояса часов"
if mutate utc-midnight "$TODAY" 's/\.atStartOfDay\(clock\.getZone\(\)\)/.atStartOfDay(java.time.ZoneOffset.UTC)/' \
    "atStartOfDay(ZoneOffset.UTC) вместо clock.getZone()"; then
    expect_summary "$OUT" 1 0 "полночь по UTC"
    expect_green "$OUT" "$T1" "первый зелёный — его данные ошибку не видят"
    expect_red "$OUT" "$T2" "красный только второй — граница дня"
    expect_contains "$(actual_parts "$OUT")" "человек-8" "в списке — задача на 00:00 по Москве"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: LocalDate.now() без часов"
today=$(date -u +%F)
if [[ "$today" < "2026-10-09" ]]; then
    note "сегодня $today: «настоящее сегодня» слишком близко к 5 октября — мутация не показательна, пропущена"
elif mutate local-date-now "$TODAY" 's/LocalDate\.now\(clock\)/LocalDate.now()/' "LocalDate.now() без часов"; then
    expect_summary "$OUT" 2 0 "LocalDate.now() — сегодня $today, а не 5 октября"
    expect_red "$OUT" "$T1" "красный первый"
    expect_red "$OUT" "$T2" "красный второй"
    expect_green "$OUT" "$T3" "третий зелёный"
    show "$(red_detail "$OUT")"
    guard=$(java "${UTF8[@]}" -cp "$PROBE_CP" example.gameday.journal.CrmProbe guard "$MUTANT/$TODAY" 2>&1)
    expect_line "$guard" "сторож: TodayList.java → 0" "сторож статьи 11 на этом TodayList промолчал бы"
fi

section "Что будет, если: без проверки в компактном конструкторе"
if mutate no-due-check "$FOLLOW_UP" 's/\s*if \(dueAt == null\) \{[^}]*\}\n//s' \
    "FollowUp без if (dueAt == null)" -0pi; then
    expect_not_contains "$(cat "$MUTANT/$FOLLOW_UP")" "dueAt == null" "проверки в варианте нет"
    expect_summary "$OUT" 1 0 "без проверки"
    expect_green "$OUT" "$T1" "первый зелёный"
    expect_green "$OUT" "$T2" "второй зелёный"
    expect_red "$OUT" "$T3" "красный третий — задача без срока создалась"
    show "$(red_detail "$OUT")"
fi

section "Первоисточники открываются"
for link in https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Clock.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/LocalDate.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Comparator.html \
    https://www.postgresql.org/docs/current/queries-order.html; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
