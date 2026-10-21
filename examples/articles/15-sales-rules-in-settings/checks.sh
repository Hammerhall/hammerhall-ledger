# Статья 15 «Правила продаж — в настройках» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 14: журнал в example.gameday.journal (18 файлов, 2 миграции), сторожа GameDayRulesTest
# (43 запуска), модель статей 12–14 в example.crm — FollowUp, TodayList, OrdinalDemo, FunnelNumbers, Discount,
# PriceBreakdown, Checkout, Rubles и их тесты. Код статьи — чистая Java: ReminderPoint в src/main/java/example/crm,
# ReminderPointTest в src/test/java/example/crm. В mvn verify он уже прошёл. Здесь — то, что статья обещает словами:
# 8 запусков теста и 43 у сторожа статьи 11; код без Spring рядом с корнем пакетов, короткие куски в тексте — те же,
# что в «Пример целиком»; таблица строк теста по Москве, календарь окна 14 / 7 / 5 и сорванные ночи, 💡 Парижа,
# FollowUp и список на сегодня, время брони, пояс Москвы, пауза, «одна плохая строка» и флаг прерывания — на самой
# модели и на java.time; cron, «-» и пояса — тем же разбором Spring, что у @Scheduled (CronExpression,
# StringUtils.parseTimeZoneString); в настоящем контексте Spring — @EnableScheduling, ${…:умолчание}, «-»,
# ошибки старта, метод с параметром, классы настроек с @Validated, @Component и переменная окружения; YAML
# из текста статьи — загрузчиком Boot, с кавычками и без; javac: расписание из объекта настроек и sleep без catch;
# «что будет, если» — мутации ReminderPoint: какие строки таблицы краснеют и что приходит вместо ожидаемого;
# первоисточники открываются. Мутации гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в 11–14.

CLS=example.crm.ReminderPointTest
CRM=src/main/java/example/crm
CRM_TEST=src/test/java/example/crm
POINT=$CRM/ReminderPoint.java
POINT_TEST=$CRM_TEST/ReminderPointTest.java
HERE=$PWD
ARTICLE=${ROOT:-}/articles/15-sales-rules-in-settings.md

# Строки таблицы ReminderPointTest: правило, конец абонемента, «сейчас», ожидание — как в статье.
ROWS='7 2026-10-11T21:00:00Z 2026-09-27T23:00:00Z 2026-10-04T21:00:00Z
10 2026-10-11T21:00:00Z 2026-09-27T23:00:00Z 2026-10-01T21:00:00Z
7 2026-10-11T21:00:00Z 2026-10-04T23:00:00Z 2026-10-04T23:00:00Z
7 2026-10-11T21:00:00Z 2026-10-04T21:00:00Z 2026-10-04T21:00:00Z
7 2026-10-11T21:00:00Z 2026-10-04T21:00:01Z 2026-10-04T21:00:01Z'

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

# Строка, которая начинается так, и в ней есть кусок. Аргументы: текст, начало строки, кусок, пояснение.
expect_line_with() {
    if grep -F -- "$2" <<<"$1" | grep -qF -- "$3"; then pass "$4"; else fail "$4: в строке «$2…» нет «$3»"; fi
}

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
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 24; }

# Тест красный / зелёный в дереве. Аргументы: вывод, имя метода, пояснение.
expect_red()   { if red_lines "$1" | grep -qF -- "$2()"; then pass "$3"; else fail "$3: $2 не красный"; fi; }
expect_green() { if grep -qF -- "$2() ✔" <<<"$1"; then pass "$3"; else fail "$3: $2 не зелёный"; fi; }

# Подпись строки таблицы в дереве — «за "7" дн., сейчас "2026-…" → "2026-…"» по name = "за {0} дн., сейчас {2} → {3}»;
# кавычки вокруг аргументов JUnit ставит сам, здесь они необязательны. Аргумент: номер строки таблицы, 1–5.
row_re() {
    local days now expected
    read -r days _ now expected < <(sed -n "${1}p" <<<"$ROWS")
    printf 'за "?%s"? дн\\., сейчас "?%s"? → "?%s"?' "$days" "$now" "$expected"
}

# Строка таблицы красная / зелёная. Аргументы: вывод, номер строки, пояснение.
expect_red_row() {
    if red_lines "$1" | LC_ALL=C.UTF-8 grep -qE -- "$(row_re "$2")"; then pass "$3"; else fail "$3: строка $2 не красная"; fi
}
expect_green_row() {
    if LC_ALL=C.UTF-8 grep -qE -- "$(row_re "$2") ✔" <<<"$1"; then pass "$3"; else fail "$3: строка $2 не зелёная"; fi
}

# Правка варианта должна что-то поменять. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    return 0
}

# Собрать код example.crm и тест статьи в $1/classes — без target/classes песочницы.
compile_crm() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$CRM"/*.java "$1/$POINT_TEST" >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): example.crm не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# ReminderPointTest в ConsoleLauncher на классах из $1.
crm_test() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" --select-class "$CLS" 2>&1
}

# Вариант: правка ReminderPoint (perl), сборка, прогон теста. Вывод — в $OUT, код выхода — в $CODE, папка — в $MUTANT.
# Аргументы: имя варианта, perl-правка, что правили, флаги perl (необязательно).
OUT=""
CODE=0
MUTANT=""
variant() {
    local name=$1 edit=$2 what=$3 flags=${4:--pi} v
    OUT=""
    CODE=0
    v=$(make_variant "$name")
    MUTANT=$v
    perl "$flags" -e "$edit" "$v/$POINT"
    expect_changed "$v/$POINT" "$POINT" "$what" || return 1
    pass "в варианте: $what"
    compile_crm "$v" || return 1
    OUT=$(crm_test "$v/classes")
    CODE=$?
}

# Блок кода статьи: первый ```<язык> после строки-заголовка. Аргументы: заголовок (начало строки), язык.
article_block() {
    awk -v head="$1" -v lang="$2" 'index($0, head) == 1 { on = 1; next }
        on && $0 == "```" lang { inside = 1; next }
        inside && /^```$/ { exit }
        inside { print }' "$ARTICLE"
}

# Блок кода статьи, который начинается с этой строки. Аргумент: первая строка блока.
article_block_from() {
    awk -v first="$1" '/^```/ && !inside { inside = 1; buf = ""; n = 0; next }
        inside && /^```$/ { inside = 0; if (keep) { printf "%s", buf; exit } next }
        inside { if (n == 0) keep = ($0 == first); buf = buf $0 "\n"; n++ }' "$ARTICLE"
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CLS" 8
note "8 запусков ReminderPointTest: пять строк таблицы, две строки «правило без дней» и тест про часы"
suite_ok example.crm.CheckoutTest 11
suite_ok example.crm.RublesTest 5
suite_ok example.crm.FunnelNumbersTest 13
suite_ok example.crm.TodayListTest 3
suite_ok example.gameday.journal.GameDayRulesTest 43
note "у сторожа статьи 11 по-прежнему 43 запуска: в папку журнала новый класс не попал, миграций не прибавилось"
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

section "Код статьи — чистая Java рядом с корнем пакетов; короткие куски — те же, что в «Пример целиком»"
src=$(cat "$POINT")
expect_not_contains "$src" "org.springframework" "в ReminderPoint нет ни одного импорта Spring"
expect_not_contains "$src" "@Component" "…и ни одной аннотации компонента"
expect_contains "$src" "package example.crm;" "код статьи — в example.crm: рядом с корнем example.gameday, не внутри"
for file in FollowUp TodayList OrdinalDemo FunnelNumbers Discount PriceBreakdown Checkout Rubles; do
    expect_file "$CRM/$file.java"
done
for file in TodayListTest FunnelNumbersTest CheckoutTest RublesTest; do expect_file "$CRM_TEST/$file.java"; done
expect_regex "$(find src/main/java/example/gameday/journal -name '*.java' | grep -c '')" '^18$' \
    "в папке журнала по-прежнему 18 файлов — их и обходит сторож статьи 11"
expect_regex "$(find src/main/resources/db/migration -name '*.sql' | grep -c '')" '^2$' "миграций по-прежнему две"
expect_regex "$(grep -rlE '@Scheduled|@EnableScheduling' src/main/java | grep -c '')" '^0$' \
    "в песочнице ни одного @Scheduled и @EnableScheduling: расписаний у журнала нет"
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    short=$(article_block "### Свой код: ReminderPoint" java)
    expect_regex "$(grep -c 'public final class ReminderPoint' <<<"$short")" '^1$' "в части 2 — короткий ReminderPoint"
    missing=$(grep -v '^$' <<<"$short" | grep -vxF -f "$POINT")
    if [ -z "$missing" ]; then pass "каждая строка короткого ReminderPoint — в файле «Пример целиком»"
    else fail "строк короткого ReminderPoint нет в файле"; show "$missing"; fi
    short=$(article_block "### Тест на остановленных часах" java)
    expect_contains "$short" "void remindsBeforeUntilButNotInThePast" "в части 2 — таблица теста"
    missing=$(grep -v '^$' <<<"$short" | grep -vxF -f "$POINT_TEST")
    if [ -z "$missing" ]; then pass "каждая строка таблицы теста в тексте — в ReminderPointTest «Пример целиком»"
    else fail "строк теста из текста нет в файле"; show "$missing"; fi
fi
out=$(crm_test "$HERE/target/test-classes:$HERE/target/classes"); code=$?
expect_ok "$code" "ConsoleLauncher: ReminderPointTest на песочнице"
expect_summary "$out" 0 0 "ReminderPointTest"
expect_regex "$(summary_of "$out" 'tests successful')" '^8$' "зелёных 8"
for n in 1 2 3 4 5; do expect_green_row "$out" "$n" "строка $n таблицы зелёная"; done
expect_regex "$out" 'за "?0"? дн\. — ошибка ✔' "«за 0 дн.» — ошибка, зелёная"
expect_regex "$out" 'за "?-7"? дн\. — ошибка ✔' "«за -7 дн.» — ошибка, зелёная"
expect_green "$out" rejectsMissingClock "rejectsMissingClock зелёный"
show "$(grep -E '✔|✘' <<<"$out" | grep -vE 'JUnit|ReminderPointTest ')"

section "Таблица, календарь, Париж, задача и пояс — на самой модели"
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/ReminderProbe.java" <<'EOF'
package example.gameday.journal;

import example.crm.FollowUp;
import example.crm.ReminderPoint;
import example.crm.TodayList;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.zone.ZoneOffsetTransition;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Проба для checks.sh статьи 15: печатает то, что статья обещает словами, — на самой ReminderPoint.
// В статью не идёт. Пакет — журнала: GameDayRules статьи 11 виден только из него.
public class ReminderProbe {

    static final ZoneId MSK = ZoneId.of("Europe/Moscow");
    static final ZoneId PARIS = ZoneId.of("Europe/Paris");
    static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM").withZone(MSK);
    static final DateTimeFormatter DAY_TIME = DateTimeFormatter.ofPattern("dd.MM HH:mm").withZone(MSK);
    static final DateTimeFormatter DAY_TIME_S = DateTimeFormatter.ofPattern("dd.MM HH:mm:ss").withZone(MSK);
    // Конец абонемента в статье — 12 октября 2026, 00:00 по Москве.
    static final Instant UNTIL = LocalDate.of(2026, 10, 12).atStartOfDay(MSK).toInstant();

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].equals("guard")) {
            for (int i = 1; i < args.length; i++) {
                Path file = Path.of(args[i]);
                System.out.println("сторож: " + file.getFileName() + " → "
                        + GameDayRules.instantNowCalls(Files.readString(file)).size());
            }
            return;
        }
        System.out.println("конец абонемента: " + UNTIL);
        // Строки таблицы ReminderPointTest — прямо из файла теста (args[1]), по Москве — как таблица статьи.
        String test = Files.readString(Path.of(args[1]));
        Matcher m = Pattern.compile("(?m)^\\s*(\\d+)\\s*\\|\\s*(\\S+)\\s*\\|\\s*(\\S+)\\s*\\|\\s*(\\S+)\\s*$").matcher(test);
        int n = 0;
        while (m.find()) {
            n++;
            int days = Integer.parseInt(m.group(1));
            Instant until = Instant.parse(m.group(2));
            Instant now = Instant.parse(m.group(3));
            Instant expected = Instant.parse(m.group(4));
            Instant got = new ReminderPoint(days, Clock.fixed(now, ZoneOffset.UTC)).remindAt(until);
            boolean passed = until.minus(Duration.ofDays(days)).isBefore(now);
            System.out.println("строка теста " + n + ": конец " + until + ", ожидание сходится с моделью: "
                    + got.equals(expected));
            System.out.println("| " + n + " | " + days + " дней | " + moment(now) + " | " + moment(got)
                    + (passed ? " — сейчас" : "") + " |");
        }
        System.out.println("строк в таблице теста: " + n);
        // Календарь части 2: обход каждую ночь в 2:00 по Москве, правило 7 дней.
        for (int window : new int[] {14, 7, 5}) {
            List<LocalDate> seen = nightsWithRow(window);
            System.out.println("окно " + window + ": строка в ответе ночами " + DAY.format(at2(seen.get(0))) + "–"
                    + DAY.format(at2(seen.get(seen.size() - 1))) + ", ночей " + seen.size()
                    + "; первая задача — " + task(window, Set.of()));
        }
        System.out.println("ночь 12.10 в ответе: " + nightsWithRow(14).contains(LocalDate.of(2026, 10, 12)));
        System.out.println("окно 14, не удались 6 ночей с 28.09: " + task(14, failed("2026-09-28", 6)));
        System.out.println("окно 14, не удались 7 ночей с 28.09: " + task(14, failed("2026-09-28", 7)));
        System.out.println("окно 14, не удались 13 ночей с 28.09: " + task(14, failed("2026-09-28", 13)));
        System.out.println("окно 14, не удались 14 ночей с 28.09: " + task(14, failed("2026-09-28", 14)));
        System.out.println("окно 7, не удалась ночь 05.10: " + task(7, failed("2026-10-05", 1)));
        System.out.println("окно 7, не удались 2 ночи с 05.10: " + task(7, failed("2026-10-05", 2)));
        System.out.println("окно 7, не удались 7 ночей с 05.10: " + task(7, failed("2026-10-05", 7)));
        for (int window : new int[] {14, 7}) {
            int lost = 0;
            LocalDate first = nightsWithRow(window).get(0);
            while (sameDay(task(window, failed(first.toString(), lost + 1)))) {
                lost++;
            }
            System.out.println("окно " + window + ": ночей подряд без сдвига на другой день — " + lost);
        }
        Instant five = taskAt(5, Set.of());
        Instant rule = UNTIL.minus(Duration.ofDays(7));
        System.out.println("окно 5: позже правила на " + Duration.between(rule, five).toDays() + " дн.");
        // Точка в прошлом: CRM узнала об абонементе за три дня до конца.
        Instant late = UNTIL.minus(Duration.ofDays(3));
        System.out.println("узнала за 3 дня: точка " + Duration.between(rule, late).toDays()
                + " дн. назад, срок задачи — сейчас: " + new ReminderPoint(7, Clock.fixed(late, MSK)).remindAt(UNTIL)
                .equals(late));
        // Неделя — 168 часов; в Париже — через переход на зимнее время.
        System.out.println("Duration.ofDays(7): " + Duration.ofDays(7));
        ZoneOffsetTransition back = PARIS.getRules().nextTransition(Instant.parse("2026-10-01T00:00:00Z"));
        System.out.println("Париж, переход: " + back.getDateTimeBefore().toLocalDate() + ", " + back.getOffsetBefore()
                + " → " + back.getOffsetAfter());
        Instant parisUntil = LocalDate.of(2026, 11, 1).atStartOfDay(PARIS).toInstant();
        Instant parisPoint = new ReminderPoint(7, Clock.fixed(Instant.parse("2026-10-01T00:00:00Z"), PARIS))
                .remindAt(parisUntil);
        System.out.println("Париж, 168 часов до полуночи 01.11: " + parisPoint.atZone(PARIS).toLocalDateTime());
        System.out.println("Париж, minusDays(7) в поясе: "
                + parisUntil.atZone(PARIS).minusDays(7).toInstant().atZone(PARIS).toLocalDateTime());
        // Задача продления — FollowUp статьи 12: срок задачи из модели, срок предмета — конец абонемента.
        Instant night = at2(LocalDate.of(2026, 9, 28));
        FollowUp renewal = new FollowUp("RENEWAL", "человек-1",
                new ReminderPoint(7, Clock.fixed(night, MSK)).remindAt(UNTIL), UNTIL, false);
        System.out.println("задача ночи 28.09: dueAt " + DAY_TIME.format(renewal.dueAt()) + ", untilAt "
                + DAY_TIME.format(renewal.untilAt()));
        for (String noon : List.of("2026-10-04T09:00:00Z", "2026-10-05T09:00:00Z")) {
            Clock clock = Clock.fixed(Instant.parse(noon), MSK);
            System.out.println("в списке на сегодня " + DAY.format(Instant.parse(noon)) + ": "
                    + new TodayList(clock).select(List.of(renewal)).contains(renewal));
        }
        // Тексты ошибок модели.
        for (int days : new int[] {0, -7}) {
            try {
                new ReminderPoint(days, Clock.systemUTC());
                System.out.println("за " + days + " дн.: создана");
            } catch (IllegalArgumentException e) {
                System.out.println("за " + days + " дн.: " + e.getMessage());
            }
        }
        try {
            new ReminderPoint(7, null);
            System.out.println("без часов: создана");
        } catch (NullPointerException e) {
            System.out.println("без часов: NullPointerException: " + e.getMessage());
        }
        // Часть 3: время брони в тексте задачи.
        Instant heldUntil = Instant.parse("2026-10-06T08:00:00Z");
        DateTimeFormatter moment = DateTimeFormatter.ofPattern("dd.MM HH:mm xxx");
        System.out.println("бронь как есть: " + heldUntil);
        System.out.println("бронь по Москве: " + moment.format(heldUntil.atZone(MSK)));
        System.out.println("тот же момент: " + heldUntil.atZone(MSK).toInstant().equals(heldUntil));
        // Москва: +03:00 круглый год, без переходов после 2014 года.
        System.out.println("Москва: январь " + MSK.getRules().getOffset(Instant.parse("2026-01-15T00:00:00Z"))
                + ", июль " + MSK.getRules().getOffset(Instant.parse("2026-07-15T00:00:00Z")));
        System.out.println("Москва: следующий переход после 2026-10-21 — "
                + MSK.getRules().nextTransition(Instant.parse("2026-10-21T00:00:00Z"))
                + ", правил переходов — " + MSK.getRules().getTransitionRules().size());
        System.out.println("Москва: последний переход — "
                + MSK.getRules().previousTransition(Instant.parse("2026-10-21T00:00:00Z")).getDateTimeBefore()
                .toLocalDate());
        for (String date : List.of("2026-01-15", "2026-07-15")) {
            ZonedDateTime two = LocalDate.parse(date).atTime(2, 0).atZone(MSK);
            System.out.println("2:00 по Москве " + date + " — " + two.toInstant());
        }
        // Часть 4: пауза между людьми.
        long pauses = 1000;
        Duration total = Duration.ofMillis(250).multipliedBy(pauses);
        System.out.println("тысяча пауз по 250 мс: " + total + ", больше четырёх минут: "
                + (total.compareTo(Duration.ofMinutes(4)) > 0));
        // Часть 4: одна плохая строка.
        List<String> rows = List.of("человек-1", "сломанная", "человек-3");
        System.out.println("try/catch на каждой строке: " + perRow(rows));
        System.out.println("один try на весь цикл: " + wholeLoop(rows));
        // Часть 4: InterruptedException.
        Thread.currentThread().interrupt();
        long start = System.nanoTime();
        try {
            Thread.sleep(250);
            System.out.println("sleep при поднятом флаге: проспал");
        } catch (InterruptedException e) {
            long ms = (System.nanoTime() - start) / 1_000_000;
            System.out.println("sleep при поднятом флаге: InterruptedException сразу: " + (ms < 200)
                    + "; флаг после исключения: " + Thread.currentThread().isInterrupted());
        }
        Thread.interrupted();
        System.out.println("обход, флаг вернули и вышли: " + sweep(true));
        System.out.println("обход, только запись в лог: " + sweep(false));
        // Сторож статьи 11: обходит только папку журнала.
        List<Path> journal = GameDayRules.filesIn(Path.of("src/main/java/example/gameday/journal"), ".java");
        System.out.println("сторож обходит: " + journal.size() + " файлов, из example.crm — "
                + journal.stream().filter(file -> file.toString().contains("crm")).count());
        System.out.println("--- конец");
    }

    static Instant at2(LocalDate night) {
        return night.atTime(2, 0).atZone(MSK).toInstant();
    }

    static String moment(Instant at) {
        return (at.getEpochSecond() % 60 == 0 ? DAY_TIME : DAY_TIME_S).format(at);
    }

    /** Ночи, в которые система клуба отдаёт строку: конец абонемента в [сейчас; сейчас + N дней]. */
    static List<LocalDate> nightsWithRow(int window) {
        List<LocalDate> nights = new ArrayList<>();
        for (LocalDate night = LocalDate.of(2026, 9, 15); night.isBefore(LocalDate.of(2026, 10, 20));
                night = night.plusDays(1)) {
            Instant now = at2(night);
            if (!UNTIL.isBefore(now) && !UNTIL.isAfter(now.plus(Duration.ofDays(window)))) {
                nights.add(night);
            }
        }
        return nights;
    }

    static Set<LocalDate> failed(String from, int count) {
        Set<LocalDate> nights = new TreeSet<>();
        for (int i = 0; i < count; i++) {
            nights.add(LocalDate.parse(from).plusDays(i));
        }
        return nights;
    }

    /** Срок задачи из первой удачной ночи, когда строка в ответе; null — задачи не будет. */
    static Instant taskAt(int window, Set<LocalDate> failedNights) {
        for (LocalDate night : nightsWithRow(window)) {
            if (!failedNights.contains(night)) {
                return new ReminderPoint(7, Clock.fixed(at2(night), MSK)).remindAt(UNTIL);
            }
        }
        return null;
    }

    static String task(int window, Set<LocalDate> failedNights) {
        for (LocalDate night : nightsWithRow(window)) {
            if (!failedNights.contains(night)) {
                return "ночь " + DAY.format(at2(night)) + ", срок " + DAY_TIME.format(taskAt(window, failedNights));
            }
        }
        return "задачи нет";
    }

    static boolean sameDay(String task) {
        return task.endsWith("срок 05.10 00:00") || task.endsWith("срок 05.10 02:00");
    }

    static void handle(String row) {
        if (row.equals("сломанная")) {
            throw new IllegalStateException("сломанная строка");
        }
    }

    static String perRow(List<String> rows) {
        List<String> done = new ArrayList<>();
        int errors = 0;
        for (String row : rows) {
            try {
                handle(row);
                done.add(row);
            } catch (Exception e) {
                errors++;
            }
        }
        return "обработаны " + done + ", ошибок " + errors;
    }

    static String wholeLoop(List<String> rows) {
        List<String> done = new ArrayList<>();
        try {
            for (String row : rows) {
                handle(row);
                done.add(row);
            }
        } catch (Exception e) {
            return "обработаны " + done + ", дальше цикл оборвался";
        }
        return "обработаны " + done;
    }

    /** Обход с паузой между людьми; флаг прерывания поднят до вызова — как в учебном тесте. */
    static String sweep(boolean restore) {
        List<String> done = new ArrayList<>();
        Thread.currentThread().interrupt();
        for (String member : List.of("лид-1", "лид-2", "лид-3")) {
            done.add(member);
            try {
                Thread.sleep(10);
            } catch (InterruptedException e) {
                if (restore) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        boolean flag = Thread.interrupted();
        return "обработаны " + done + ", флаг виден снаружи: " + flag;
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "target/test-classes:target/classes" \
    "$PROBE/src/ReminderProbe.java" 2>&1)
expect_ok $? "javac пробы модели"
show "$out"
PROBE_CP="$PROBE/classes:target/test-classes:target/classes"
probe=$(java "${UTF8[@]}" -cp "$PROBE_CP" example.gameday.journal.ReminderProbe table "$POINT_TEST" 2>&1)
expect_contains "$probe" "--- конец" "проба модели дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"
expect_line "$probe" "конец абонемента: 2026-10-11T21:00:00Z" "12 октября, 00:00 по Москве — 21:00 по UTC накануне"
expect_line "$probe" "строк в таблице теста: 5" "в таблице теста пять строк"
expect_regex "$(grep -c 'ожидание сходится с моделью: true' <<<"$probe")" '^5$' "ожидания всех пяти строк — то, что даёт модель"
expect_regex "$(grep -c 'конец 2026-10-11T21:00:00Z' <<<"$probe")" '^5$' "конец абонемента во всех строках один"
if [ -f "$ARTICLE" ]; then
    while IFS= read -r row; do
        if grep -qF -- "$row" "$ARTICLE"; then pass "таблица статьи по Москве: $row"
        else fail "в статье нет строки таблицы «$row»"; fi
    done < <(grep '^| [1-5] |' <<<"$probe")
fi
show "$(grep -E '^\| [1-5] \|' <<<"$probe")"
expect_line "$probe" "окно 14: строка в ответе ночами 28.09–11.10, ночей 14; первая задача — ночь 28.09, срок 05.10 00:00" \
    "окно 14: строка впервые ночью 28.09, задача со сроком 05.10, 0:00"
expect_line "$probe" "окно 7: строка в ответе ночами 05.10–11.10, ночей 7; первая задача — ночь 05.10, срок 05.10 02:00" \
    "окно 7: строка впервые ночью 05.10, точка прошла два часа назад — задача «на сейчас»"
expect_line "$probe" "окно 5: строка в ответе ночами 07.10–11.10, ночей 5; первая задача — ночь 07.10, срок 07.10 02:00" \
    "💡 окно 5: строка впервые ночью 07.10"
expect_line "$probe" "ночь 12.10 в ответе: false" "12.10 абонемент кончился — строки нет"
expect_line "$probe" "окно 14, не удались 6 ночей с 28.09: ночь 04.10, срок 05.10 00:00" "шесть неудачных ночей не стоят ничего…"
expect_line "$probe" "окно 14, не удались 7 ночей с 28.09: ночь 05.10, срок 05.10 02:00" "…семь — двух часов"
expect_line "$probe" "окно 14, не удались 13 ночей с 28.09: ночь 11.10, срок 11.10 02:00" "окно 14: после 13 сорванных ночей задача ещё будет…"
expect_line "$probe" "окно 14, не удались 14 ночей с 28.09: задачи нет" "…после четырнадцати — нет"
expect_line "$probe" "окно 7, не удалась ночь 05.10: ночь 06.10, срок 06.10 02:00" "окно 7: неудачная ночь 05.10 сдвигает на сутки…"
expect_line "$probe" "окно 7, не удались 2 ночи с 05.10: ночь 07.10, срок 07.10 02:00" "…каждая следующая — ещё на сутки"
expect_line "$probe" "окно 7, не удались 7 ночей с 05.10: задачи нет" "окно 7: не удались все семь — напоминания не будет"
expect_line "$probe" "окно 14: ночей подряд без сдвига на другой день — 7" "🔑 запас без сдвига на другой день: 14 − 7 = 7"
expect_line "$probe" "окно 7: ночей подряд без сдвига на другой день — 0" "…а у окна 7 — ноль"
expect_line "$probe" "окно 5: позже правила на 2 дн." "💡 окно 5: напоминание на два дня позже правила"
expect_line "$probe" "узнала за 3 дня: точка 4 дн. назад, срок задачи — сейчас: true" \
    "узнала за три дня до конца: точка четыре дня назад, срок — «сейчас»"
expect_line "$probe" "Duration.ofDays(7): PT168H" "Duration.ofDays(7) — 168 часов"
expect_line "$probe" "Париж, переход: 2026-10-25, +02:00 → +01:00" "💡 в Париже 25 октября 2026 часы переводят назад"
expect_line "$probe" "Париж, 168 часов до полуночи 01.11: 2026-10-25T01:00" "💡 за 168 часов до полуночи 1 ноября — 01:00…"
expect_line "$probe" "Париж, minusDays(7) в поясе: 2026-10-25T00:00" "💡 …а minusDays(7) в поясе — полночь"
expect_line "$probe" "задача ночи 28.09: dueAt 05.10 00:00, untilAt 12.10 00:00" \
    "FollowUp статьи 12: срок задачи — точка напоминания, срок предмета — конец абонемента"
expect_line "$probe" "в списке на сегодня 04.10: false" "4 октября задачи в списке на сегодня ещё нет…"
expect_line "$probe" "в списке на сегодня 05.10: true" "…5 октября срок наступил — она в списке"
expect_line "$probe" "за 0 дн.: напоминаем хотя бы за день, а пришло 0" "правило за 0 дней — исключение с текстом"
expect_line "$probe" "за -7 дн.: напоминаем хотя бы за день, а пришло -7" "…и за −7"
expect_line "$probe" "без часов: NullPointerException: часы не заданы" "без часов — NullPointerException «часы не заданы»"
expect_line "$probe" "бронь как есть: 2026-10-06T08:00:00Z" "бронь как есть — 2026-10-06T08:00:00Z, «до восьми утра»…"
expect_line "$probe" "бронь по Москве: 06.10 11:00 +03:00" "…с пересчётом — 06.10 11:00 +03:00"
expect_line "$probe" "тот же момент: true" "atZone — тот же момент на часах пояса"
expect_line "$probe" "Москва: январь +03:00, июль +03:00" "у Москвы круглый год +03:00"
expect_line "$probe" "Москва: следующий переход после 2026-10-21 — null, правил переходов — 0" "у Москвы летнего времени нет…"
expect_line "$probe" "Москва: последний переход — 2014-10-26" "…с 2014 года"
expect_line "$probe" "2:00 по Москве 2026-01-15 — 2026-01-14T23:00:00Z" "2:00 по Москве — 23:00 по UTC накануне зимой…"
expect_line "$probe" "2:00 по Москве 2026-07-15 — 2026-07-14T23:00:00Z" "…и летом"
expect_line "$probe" "тысяча пауз по 250 мс: PT4M10S, больше четырёх минут: true" "тысяча человек с паузой 250 мс — больше четырёх минут"
expect_line "$probe" "try/catch на каждой строке: обработаны [человек-1, человек-3], ошибок 1" \
    "try/catch на каждой строке: плохая строка — в лог, остальные обработаны"
expect_line "$probe" "один try на весь цикл: обработаны [человек-1], дальше цикл оборвался" \
    "без него первая плохая строка обрывает цикл"
expect_line "$probe" "sleep при поднятом флаге: InterruptedException сразу: true; флаг после исключения: false" \
    "флаг стоит до sleep — исключение сразу, и флаг после него сброшен"
expect_line "$probe" "обход, флаг вернули и вышли: обработаны [лид-1], флаг виден снаружи: true" \
    "вернули флаг и вышли: обработан первый, флаг на месте"
expect_line "$probe" "обход, только запись в лог: обработаны [лид-1, лид-2, лид-3], флаг виден снаружи: false" \
    "только запись в лог: обход идёт по всем, просьба потеряна"
expect_line "$probe" "сторож обходит: 18 файлов, из example.crm — 0" "сторож статьи 11 смотрит только в папку журнала"
show "$(grep -vE '^(\| [1-5] \||строка теста|--- конец)' <<<"$probe")"
guard=$(java "${UTF8[@]}" -cp "$PROBE_CP" example.gameday.journal.ReminderProbe guard "$POINT" 2>&1)
expect_line "$guard" "сторож: ReminderPoint.java → 0" "правило сторожа ReminderPoint держит и так: «сейчас» только из часов"

section "cron, «-» и пояс — тем же разбором Spring, что у @Scheduled"
cp_jars=$(tr ':' '\n' <<<"$TEST_DEPS" | sed 's#.*/##')
expect_regex "$cp_jars" '^spring-context-[0-9]' "spring-context в песочнице есть — @Scheduled и CronExpression из него…"
expect_not_contains "$(cat pom.xml)" "<artifactId>spring-context</artifactId>" "…а в pom.xml его нет: приехал со стартером Boot"
cat >"$PROBE/src/CronProbe.java" <<'EOF'
package example.probe;

import java.time.DayOfWeek;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.support.CronExpression;
import org.springframework.util.StringUtils;

// Проба для checks.sh статьи 15: cron и пояс — тем же разбором Spring, что у @Scheduled. В статью не идёт.
public class CronProbe {

    static final ZoneId MSK = ZoneId.of("Europe/Moscow");
    static final DateTimeFormatter AT = DateTimeFormatter.ofPattern("dd.MM HH:mm:ss");

    public static void main(String[] args) {
        ZonedDateTime from = ZonedDateTime.of(2026, 10, 5, 1, 50, 0, 0, MSK);
        for (String cron : List.of("0 0 2 * * *", "0 30 2 * * *", "0 15/30 * * * *", "0 0/30 * * * *",
                "0 2 * * * *", "*/10 * * * * *")) {
            System.out.println("cron " + cron + " после 05.10 01:50 МСК: " + next(cron, from, 4));
        }
        ZonedDateTime day = ZonedDateTime.of(2026, 10, 5, 0, 0, 0, 0, MSK);
        for (String cron : List.of("0 0 2 * * *", "0 2 * * * *")) {
            System.out.println("cron " + cron + " за сутки 05.10: " + count(cron, day, day.plusDays(1)));
        }
        for (String cron : List.of("0 0 2 * * 0", "0 0 2 * * 7")) {
            DayOfWeek dow = CronExpression.parse(cron).next(from).getDayOfWeek();
            System.out.println("cron " + cron + ": " + dow);
        }
        String[] names = {"секунда", "минута", "час", "день месяца", "месяц", "день недели"};
        for (int field = 0; field < 6; field++) {
            List<Integer> valid = new ArrayList<>();
            for (int value = -1; value <= 61; value++) {
                String[] parts = {"0", "0", "0", "*", "*", "*"};
                parts[field] = String.valueOf(value);
                if (CronExpression.isValidExpression(String.join(" ", parts))) {
                    valid.add(value);
                }
            }
            boolean solid = valid.get(valid.size() - 1) - valid.get(0) + 1 == valid.size();
            System.out.println("поле " + names[field] + ": " + valid.get(0) + "–" + valid.get(valid.size() - 1)
                    + (solid ? "" : " с дырами"));
        }
        for (String cron : List.of("0 2 * * *", "0 0 25 * * *", "-")) {
            try {
                CronExpression.parse(cron);
                System.out.println("разбор «" + cron + "»: принят");
            } catch (IllegalArgumentException e) {
                System.out.println("разбор «" + cron + "»: " + e.getMessage());
            }
        }
        System.out.println("isValidExpression(\"-\"): " + CronExpression.isValidExpression("-"));
        System.out.println("Scheduled.CRON_DISABLED: \"" + Scheduled.CRON_DISABLED + "\"");
        System.out.println("0 0 2 * * * по Москве в UTC: "
                + CronExpression.parse("0 0 2 * * *").next(from).toInstant());
        // Без zone — пояс машины: «2:00» на её часах, а сколько это по Москве?
        for (String[] machine : new String[][] {{"UTC", "2026-10-05T00:00:00Z"}, {"Europe/Paris", "2026-07-01T00:00:00Z"},
                {"Europe/Paris", "2026-12-01T00:00:00Z"}}) {
            ZonedDateTime start = ZonedDateTime.parse(machine[1]).withZoneSameInstant(ZoneId.of(machine[0]));
            ZonedDateTime fire = CronExpression.parse("0 0 2 * * *").next(start);
            System.out.println("без zone, машина " + machine[0] + " (" + machine[1].substring(0, 7) + "): 2:00 — это "
                    + fire.withZoneSameInstant(MSK).toLocalTime() + " по Москве");
        }
        for (String zone : List.of("Europe/Moscow", "Europe/Moskow", "MSK")) {
            try {
                System.out.println("zone «" + zone + "»: " + StringUtils.parseTimeZoneString(zone).toZoneId());
            } catch (IllegalArgumentException e) {
                System.out.println("zone «" + zone + "»: " + e.getMessage());
            }
        }
        // Расписания и пояса из YAML статьи — аргументами: cron=… и zone=….
        for (String arg : args) {
            String value = arg.substring(arg.indexOf('=') + 1);
            if (arg.startsWith("cron=")) {
                System.out.println("cron из статьи «" + value + "»: "
                        + (CronExpression.isValidExpression(value) ? "принят" : "не принят"));
            } else if (arg.startsWith("zone=")) {
                try {
                    System.out.println("zone из статьи «" + value + "»: принят, "
                            + StringUtils.parseTimeZoneString(value).toZoneId());
                } catch (IllegalArgumentException e) {
                    System.out.println("zone из статьи «" + value + "»: " + e.getMessage());
                }
            }
        }
        System.out.println("--- конец");
    }

    static String next(String cron, ZonedDateTime from, int times) {
        CronExpression expression = CronExpression.parse(cron);
        List<String> fires = new ArrayList<>();
        ZonedDateTime at = from;
        for (int i = 0; i < times; i++) {
            at = expression.next(at);
            fires.add(AT.format(at));
        }
        return String.join(", ", fires);
    }

    static int count(String cron, ZonedDateTime from, ZonedDateTime to) {
        CronExpression expression = CronExpression.parse(cron);
        int n = 0;
        for (ZonedDateTime at = expression.next(from.minusSeconds(1)); at.isBefore(to); at = expression.next(at)) {
            n++;
        }
        return n;
    }
}
EOF
cat >"$PROBE/src/ContextProbe.java" <<'EOF'
package example.probe;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.env.SystemEnvironmentPropertySource;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.annotation.ScheduledAnnotationBeanPostProcessor;
import org.springframework.scheduling.config.CronTask;
import org.springframework.scheduling.config.ScheduledTask;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

// Проба для checks.sh статьи 15: @Scheduled, @EnableScheduling, «-», ошибки старта, настройки-классы
// и YAML — в настоящем контексте Spring и загрузчиком Boot. Классы — как куски учебной CRM статьи,
// геттеры и сеттеры написаны руками: Lombok в песочнице нет. В статью не идёт.
public class ContextProbe {

    static final AtomicInteger TICKS = new AtomicInteger();
    static String failure = "";

    /** Обход продлений учебной CRM: расписание и пояс — из настроек, с умолчаниями. */
    public static class RenewalsSweep {
        @Scheduled(cron = "${club.sales.renewals.poll-cron:0 0 2 * * *}",
                zone = "${club.sales.renewals.poll-zone:Europe/Moscow}")
        public void pollEndingMemberships() {
        }
    }

    /** Задание, которое видно по счётчику: зовут — растёт. */
    public static class Ticker {
        @Scheduled(fixedDelay = 20)
        public void tick() {
            TICKS.incrementAndGet();
        }
    }

    /** Метод с параметром — так нельзя. */
    public static class WithParameter {
        @Scheduled(fixedDelay = 20)
        public void tick(String who) {
        }
    }

    @Configuration(proxyBeanMethods = false)
    @EnableScheduling
    public static class SchedulingOn {
    }

    @Validated
    @ConfigurationProperties(prefix = "club.sales.renewals")
    public static class RenewalsSettings {
        @Min(1)
        private int daysBefore = 7;
        @Min(1)
        @Max(90)
        private int pollWindowDays = 14;

        public int getDaysBefore() {
            return daysBefore;
        }

        public void setDaysBefore(int daysBefore) {
            this.daysBefore = daysBefore;
        }

        public int getPollWindowDays() {
            return pollWindowDays;
        }

        public void setPollWindowDays(int pollWindowDays) {
            this.pollWindowDays = pollWindowDays;
        }
    }

    @Validated
    @ConfigurationProperties(prefix = "club.sales.holds")
    public static class HoldsSettings {
        @Min(24)
        @Max(48)
        private int pollWindowHours = 48;

        public int getPollWindowHours() {
            return pollWindowHours;
        }

        public void setPollWindowHours(int pollWindowHours) {
            this.pollWindowHours = pollWindowHours;
        }
    }

    /** Класс настроек с @Component — Boot заполняет его как обычный бин. */
    @Component
    @Validated
    @ConfigurationProperties(prefix = "club.sales.offers")
    public static class OffersSettings {
        @Min(1)
        private int cooldownDays = 14;

        public int getCooldownDays() {
            return cooldownDays;
        }

        public void setCooldownDays(int cooldownDays) {
            this.cooldownDays = cooldownDays;
        }
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties({RenewalsSettings.class, HoldsSettings.class})
    public static class SettingsOn {
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties
    public static class BindingOnly {
    }

    public static void main(String[] args) throws Exception {
        try {
            scheduling();
            settings();
            for (String arg : args) {
                yaml(arg.substring(0, arg.indexOf('=')), Path.of(arg.substring(arg.indexOf('=') + 1)));
            }
        } finally {
            System.out.println("--- конец");
            System.exit(0);
        }
    }

    static void scheduling() throws InterruptedException {
        say("расписание по умолчанию", Map.of(), SchedulingOn.class, RenewalsSweep.class);
        say("poll-cron из настроек", Map.of("club.sales.renewals.poll-cron", "0 30 2 * * *"),
                SchedulingOn.class, RenewalsSweep.class);
        say("poll-cron=-", Map.of("club.sales.renewals.poll-cron", "-"), SchedulingOn.class, RenewalsSweep.class);
        say("poll-cron=0 2 * * *", Map.of("club.sales.renewals.poll-cron", "0 2 * * *"),
                SchedulingOn.class, RenewalsSweep.class);
        say("poll-cron=0 0 25 * * *", Map.of("club.sales.renewals.poll-cron", "0 0 25 * * *"),
                SchedulingOn.class, RenewalsSweep.class);
        say("poll-zone=Europe/Moskow", Map.of("club.sales.renewals.poll-zone", "Europe/Moskow"),
                SchedulingOn.class, RenewalsSweep.class);
        say("poll-zone=MSK", Map.of("club.sales.renewals.poll-zone", "MSK"), SchedulingOn.class, RenewalsSweep.class);
        say("метод с параметром", Map.of(), SchedulingOn.class, WithParameter.class);
        for (boolean enabled : new boolean[] {false, true}) {
            TICKS.set(0);
            AnnotationConfigApplicationContext ctx = enabled
                    ? start(source(Map.of()), SchedulingOn.class, Ticker.class)
                    : start(source(Map.of()), Ticker.class);
            if (ctx == null) {
                System.out.println("счётчик, @EnableScheduling " + enabled + ": не поднялся: " + failure);
                continue;
            }
            Thread.sleep(500);
            int ticks = TICKS.get();
            ctx.close();
            System.out.println("счётчик, @EnableScheduling " + enabled + ": поднялся, вызовов за полсекунды "
                    + (ticks == 0 ? "0" : "больше нуля"));
        }
    }

    static void settings() {
        bind("настройки по умолчанию", source(Map.of()));
        for (String days : List.of("120", "91", "90")) {
            bind("poll-window-days=" + days, source(Map.of("club.sales.renewals.poll-window-days", days)));
        }
        bind("days-before=0", source(Map.of("club.sales.renewals.days-before", "0")));
        for (String hours : List.of("23", "24", "48", "49")) {
            bind("poll-window-hours=" + hours, source(Map.of("club.sales.holds.poll-window-hours", hours)));
        }
        bind("переменная CLUB_SALES_RENEWALS_DAYSBEFORE=10", new SystemEnvironmentPropertySource(
                "статья-systemEnvironment", Map.of("CLUB_SALES_RENEWALS_DAYSBEFORE", "10")));
        for (String days : List.of("7", "0")) {
            AnnotationConfigApplicationContext ctx = start(source(Map.of("club.sales.offers.cooldown-days", days)),
                    BindingOnly.class, OffersSettings.class);
            System.out.println("@Component, cooldown-days=" + days + ": " + (ctx == null ? "не поднялся: " + failure
                    : "поднялся, cooldownDays=" + ctx.getBean(OffersSettings.class).getCooldownDays()));
            if (ctx != null) {
                ctx.close();
            }
        }
    }

    static void yaml(String name, Path file) throws Exception {
        List<PropertySource<?>> sources;
        try {
            sources = new YamlPropertySourceLoader().load(name, new ByteArrayResource(Files.readAllBytes(file)));
        } catch (Exception e) {
            System.out.println("yaml " + name + ": не разобрался: " + chain(e));
            return;
        }
        List<String> values = new ArrayList<>();
        for (String key : List.of("club.sales.renewals.days-before", "club.sales.renewals.poll-window-days",
                "club.sales.renewals.poll-cron", "club.sales.renewals.poll-zone", "club.sales.holds.poll-window-hours",
                "club.sales.holds.poll-cron", "club.sales.offers.poll-pause-ms", "club.sales.offers.poll-cron")) {
            Object value = null;
            for (PropertySource<?> source : sources) {
                value = value != null ? value : source.getProperty(key);
            }
            values.add(key.substring("club.sales.".length()) + "=" + value);
        }
        System.out.println("yaml " + name + ": " + String.join("; ", values));
        if (name.equals("статья")) {
            AnnotationConfigApplicationContext ctx = new AnnotationConfigApplicationContext();
            for (PropertySource<?> source : sources) {
                ctx.getEnvironment().getPropertySources().addFirst(source);
            }
            ctx.register(SettingsOn.class, SchedulingOn.class, RenewalsSweep.class);
            try {
                ctx.refresh();
                RenewalsSettings renewals = ctx.getBean(RenewalsSettings.class);
                System.out.println("yaml статьи в контексте: daysBefore=" + renewals.getDaysBefore()
                        + ", pollWindowDays=" + renewals.getPollWindowDays() + ", pollWindowHours="
                        + ctx.getBean(HoldsSettings.class).getPollWindowHours() + ", задачи " + crons(ctx));
                ctx.close();
            } catch (RuntimeException e) {
                System.out.println("yaml статьи в контексте: не поднялся: " + chain(e));
            }
        }
    }

    static void say(String what, Map<String, Object> props, Class<?>... classes) {
        AnnotationConfigApplicationContext ctx = start(source(props), classes);
        if (ctx == null) {
            System.out.println(what + ": не поднялся: " + failure);
            return;
        }
        System.out.println(what + ": поднялся, задачи " + crons(ctx));
        ctx.close();
    }

    static void bind(String what, PropertySource<?> source) {
        AnnotationConfigApplicationContext ctx = start(source, SettingsOn.class);
        if (ctx == null) {
            System.out.println(what + ": не поднялся: " + failure);
            return;
        }
        RenewalsSettings renewals = ctx.getBean(RenewalsSettings.class);
        System.out.println(what + ": поднялся, daysBefore=" + renewals.getDaysBefore() + ", pollWindowDays="
                + renewals.getPollWindowDays() + ", pollWindowHours=" + ctx.getBean(HoldsSettings.class)
                .getPollWindowHours());
        ctx.close();
    }

    static List<String> crons(AnnotationConfigApplicationContext ctx) {
        List<String> crons = new ArrayList<>();
        for (ScheduledTask task : ctx.getBean(ScheduledAnnotationBeanPostProcessor.class).getScheduledTasks()) {
            crons.add(task.getTask() instanceof CronTask cron ? cron.getExpression() : "не cron");
        }
        return crons;
    }

    static PropertySource<?> source(Map<String, Object> props) {
        return new MapPropertySource("статья", props);
    }

    /** Контекст из классов и одного источника настроек; null — не поднялся, текст — в failure. */
    static AnnotationConfigApplicationContext start(PropertySource<?> props, Class<?>... classes) {
        AnnotationConfigApplicationContext ctx = new AnnotationConfigApplicationContext();
        ctx.getEnvironment().getPropertySources().addFirst(props);
        ctx.register(classes);
        try {
            ctx.refresh();
            return ctx;
        } catch (RuntimeException e) {
            failure = chain(e);
            return null;
        }
    }

    /** Сообщения исключения и всех его причин — одной строкой. */
    static String chain(Throwable e) {
        List<String> messages = new ArrayList<>();
        for (Throwable t = e; t != null; t = t.getCause()) {
            messages.add(t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()).replaceAll("\\s+", " "));
        }
        return String.join(" ← ", messages);
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "$TEST_DEPS" \
    "$PROBE/src/CronProbe.java" "$PROBE/src/ContextProbe.java" 2>&1)
expect_ok $? "javac проб Spring"
show "$out"
# YAML части 1 — из текста статьи: его расписания и пояса проверит тот же разбор, а ниже — загрузчик Boot.
article_args=()
if [ -f "$ARTICLE" ]; then
    article_block "### Правила продаж в application.yml" yaml >"$PROBE/article.yml"
    expect_contains "$(cat "$PROBE/article.yml")" "club:" "YAML части 1 взят из текста статьи"
    while IFS= read -r value; do article_args+=("cron=$value"); done \
        < <(sed -nE 's/^ *poll-cron: "([^"]*)".*/\1/p' "$PROBE/article.yml")
    while IFS= read -r value; do article_args+=("zone=$value"); done \
        < <(sed -nE 's/^ *poll-zone: "([^"]*)".*/\1/p' "$PROBE/article.yml")
fi
cron=$(java "${UTF8[@]}" -cp "$PROBE/classes:$TEST_DEPS" example.probe.CronProbe "${article_args[@]}" 2>&1)
expect_contains "$cron" "--- конец" "проба cron дошла до конца"
[[ "$cron" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$cron")"
expect_line "$cron" "cron 0 0 2 * * * после 05.10 01:50 МСК: 05.10 02:00:00, 06.10 02:00:00, 07.10 02:00:00, 08.10 02:00:00" \
    "0 0 2 * * * — каждый день в 2:00:00"
expect_line "$cron" "cron 0 30 2 * * * после 05.10 01:50 МСК: 05.10 02:30:00, 06.10 02:30:00, 07.10 02:30:00, 08.10 02:30:00" \
    "0 30 2 * * * — в 2:30:00"
expect_line "$cron" "cron 0 15/30 * * * * после 05.10 01:50 МСК: 05.10 02:15:00, 05.10 02:45:00, 05.10 03:15:00, 05.10 03:45:00" \
    "0 15/30 * * * * — минуты 15 и 45 каждого часа"
expect_line "$cron" "cron 0 0/30 * * * * после 05.10 01:50 МСК: 05.10 02:00:00, 05.10 02:30:00, 05.10 03:00:00, 05.10 03:30:00" \
    "0/30 — минуты 0 и 30"
expect_line "$cron" "cron 0 2 * * * * после 05.10 01:50 МСК: 05.10 02:02:00, 05.10 03:02:00, 05.10 04:02:00, 05.10 05:02:00" \
    "«починка» 0 2 * * * * — на второй минуте каждого часа…"
expect_line "$cron" "cron 0 2 * * * * за сутки 05.10: 24" "…24 раза в сутки"
expect_line "$cron" "cron 0 0 2 * * * за сутки 05.10: 1" "0 0 2 * * * — раз в сутки"
expect_line "$cron" "cron */10 * * * * * после 05.10 01:50 МСК: 05.10 01:50:10, 05.10 01:50:20, 05.10 01:50:30, 05.10 01:50:40" \
    "*/10 * * * * * — каждые 10 секунд"
expect_line "$cron" "cron 0 0 2 * * 0: SUNDAY" "день недели 0 — воскресенье…"
expect_line "$cron" "cron 0 0 2 * * 7: SUNDAY" "…и 7 — тоже"
for field in "секунда: 0–59" "минута: 0–59" "час: 0–23" "день месяца: 1–31" "месяц: 1–12" "день недели: 0–7"; do
    expect_line "$cron" "поле $field" "таблица полей: $field"
done
expect_line "$cron" 'разбор «0 2 * * *»: Cron expression must consist of 6 fields (found 5 in "0 2 * * *")' \
    "пять полей — Cron expression must consist of 6 fields (found 5 in \"0 2 * * *\")"
expect_line_with "$cron" "разбор «0 0 25 * * *»:" "Invalid value for HourOfDay (valid values 0 - 23): 25" \
    "0 0 25 * * * — Invalid value for HourOfDay (valid values 0 - 23): 25"
expect_line "$cron" 'isValidExpression("-"): false' "сам разбор cron минуса не знает…"
expect_line "$cron" 'Scheduled.CRON_DISABLED: "-"' "…«-» — договорённость @Scheduled: CRON_DISABLED"
expect_line "$cron" "0 0 2 * * * по Москве в UTC: 2026-10-04T23:00:00Z" "2:00 по Москве — 23:00 по UTC накануне"
expect_line "$cron" "без zone, машина UTC (2026-10): 2:00 — это 05:00 по Москве" "без zone на машине в UTC «2:00» — 5:00 по Москве"
expect_line "$cron" "без zone, машина Europe/Paris (2026-07): 2:00 — это 03:00 по Москве" "…на ноутбуке в Париже летом — 3:00…"
expect_line "$cron" "без zone, машина Europe/Paris (2026-12): 2:00 — это 04:00 по Москве" "…и зимой — 4:00"
expect_line "$cron" "zone «Europe/Moscow»: Europe/Moscow" "zone Europe/Moscow принят"
expect_line "$cron" "zone «Europe/Moskow»: Invalid time zone specification 'Europe/Moskow'" \
    "опечатка Europe/Moskow — Invalid time zone specification"
expect_line "$cron" "zone «MSK»: Invalid time zone specification 'MSK'" "сокращение MSK Spring не примет"
expect_regex "$(grep -c '^cron из статьи «.*»: принят$' <<<"$cron")" '^3$' "все три poll-cron в YAML статьи — шесть полей, разбор принят"
expect_regex "$(grep -c '^zone из статьи «Europe/Moscow»: принят, Europe/Moscow$' <<<"$cron")" '^3$' \
    "все три poll-zone в YAML статьи — Europe/Moscow, принят"
show "$(grep -v '^--- конец' <<<"$cron")"

section "В контексте Spring: @EnableScheduling, \${…:умолчание}, «-», ошибки старта, настройки-классы, YAML статьи"
if [ -f "$ARTICLE" ]; then
    sed 's/poll-cron: "0 0 2 \* \* \*"/poll-cron: "-"/' "$PROBE/article.yml" >"$PROBE/quoted-dash.yml"
    sed 's/poll-cron: "0 0 2 \* \* \*"/poll-cron: -/' "$PROBE/article.yml" >"$PROBE/dash.yml"
    sed 's/poll-cron: "0 0 2 \* \* \*"/poll-cron: *\/10 * * * * */' "$PROBE/article.yml" >"$PROBE/star.yml"
    sed 's/poll-cron: "0 0 2 \* \* \*"/poll-cron: 0 0 2 * * */' "$PROBE/article.yml" >"$PROBE/plain.yml"
    for v in quoted-dash dash star plain; do
        expect_changed "$PROBE/$v.yml" "$PROBE/article.yml" "YAML $v" && pass "YAML-вариант $v: poll-cron продлений переписан"
    done
    settings=$(article_block_from "// учебная CRM клуба: настройки продления")
    for line in "@ConfigurationProperties(prefix = \"club.sales.renewals\")" "@Max(90)" "private int daysBefore = 7;" \
        "private int pollWindowDays = 14;"; do
        expect_contains "$settings" "$line" "класс настроек продления в статье: $line — как в пробе"
    done
    holds=$(article_block_from "// учебная CRM клуба: настройки броней — сокращено")
    for line in "@Min(24)" "@Max(48)" "private int pollWindowHours = 48;"; do
        expect_contains "$holds" "$line" "настройки броней в статье: $line — как в пробе"
    done
    sweep=$(article_block_from "// учебная служба обхода продлений — сокращено")
    expect_contains "$sweep" '@Scheduled(cron = "${club.sales.renewals.poll-cron:0 0 2 * * *}",' "@Scheduled в статье — как в пробе: cron…"
    expect_contains "$sweep" 'zone = "${club.sales.renewals.poll-zone:Europe/Moscow}")' "…и zone"
fi
ctx=$(java "${UTF8[@]}" -cp "$PROBE/classes:$TEST_DEPS" example.probe.ContextProbe "статья=$PROBE/article.yml" \
    "кавычки-минус=$PROBE/quoted-dash.yml" "минус=$PROBE/dash.yml" "звёздочка=$PROBE/star.yml" \
    "без-кавычек=$PROBE/plain.yml" 2>&1)
expect_contains "$ctx" "--- конец" "проба контекста дошла до конца"
[[ "$ctx" == *"--- конец"* ]] || show "$(tail -n 40 <<<"$ctx")"
mine=$(grep -E '^(расписание|poll-|метод|счётчик|настройки|days-|переменная|@Component|yaml)' <<<"$ctx")
expect_line "$ctx" "расписание по умолчанию: поднялся, задачи [0 0 2 * * *]" \
    "\${…:умолчание}: настройки нет — cron после двоеточия, 0 0 2 * * *"
expect_line "$ctx" "poll-cron из настроек: поднялся, задачи [0 30 2 * * *]" "настройка есть — Spring подставил её"
expect_line "$ctx" "poll-cron=-: поднялся, задачи []" "«-» в настройке: приложение поднялось, задание выключено"
for case in "poll-cron=0 2 * * *:|Cron expression must consist of 6 fields (found 5 in \"0 2 * * *\")" \
    "poll-cron=0 0 25 * * *:|Invalid value for HourOfDay (valid values 0 - 23): 25" \
    "poll-zone=Europe/Moskow:|Invalid time zone specification 'Europe/Moskow'" \
    "poll-zone=MSK:|Invalid time zone specification 'MSK'" \
    "метод с параметром:|Only no-arg methods may be annotated with @Scheduled"; do
    expect_line_with "$ctx" "${case%%|*} не поднялся" "${case#*|}" "старт падает: ${case%%|*} — ${case#*|}"
done
expect_line_with "$ctx" "poll-cron=0 2 * * *: не поднялся" "Encountered invalid @Scheduled method 'pollEndingMemberships'" \
    "…ошибка называет метод с @Scheduled"
expect_line "$ctx" "счётчик, @EnableScheduling false: поднялся, вызовов за полсекунды 0" \
    "⚠️ без @EnableScheduling приложение поднялось и молчит: вызовов 0, ошибки нет"
expect_line "$ctx" "счётчик, @EnableScheduling true: поднялся, вызовов за полсекунды больше нуля" "…с ним метод зовут"
expect_line "$ctx" "настройки по умолчанию: поднялся, daysBefore=7, pollWindowDays=14, pollWindowHours=48" \
    "класс настроек: умолчание — начальное значение поля"
for days in 120 91; do
    expect_line_with "$ctx" "poll-window-days=$days: не поднялся" "pollWindowDays" "poll-window-days: $days — старт падает, в ошибке поле…"
    expect_line_with "$ctx" "poll-window-days=$days: не поднялся" "rejected value [$days]" "…и значение $days"
done
expect_line "$ctx" "poll-window-days=90: поднялся, daysBefore=7, pollWindowDays=90, pollWindowHours=48" "90 — поднялся"
expect_line_with "$ctx" "days-before=0: не поднялся" "daysBefore" "days-before: 0 — старт падает (@Min(1))"
expect_line_with "$ctx" "days-before=0: не поднялся" "rejected value [0]" "…и значение 0"
for hours in 23 49; do
    expect_line_with "$ctx" "poll-window-hours=$hours: не поднялся" "pollWindowHours" "окно броней $hours — контекст не поднимается"
done
for hours in 24 48; do
    expect_line "$ctx" "poll-window-hours=$hours: поднялся, daysBefore=7, pollWindowDays=14, pollWindowHours=$hours" \
        "окно броней $hours — поднимается"
done
expect_line "$ctx" "переменная CLUB_SALES_RENEWALS_DAYSBEFORE=10: поднялся, daysBefore=10, pollWindowDays=14, pollWindowHours=48" \
    "переменная окружения CLUB_SALES_RENEWALS_DAYSBEFORE=10 перекрывает days-before"
expect_line "$ctx" "@Component, cooldown-days=7: поднялся, cooldownDays=7" "класс с сеттерами и @Component Boot заполнил как бин…"
expect_line_with "$ctx" "@Component, cooldown-days=0: не поднялся" "cooldownDays" "…и проверил: 0 — старт падает"
expect_line "$ctx" "yaml статья: renewals.days-before=7; renewals.poll-window-days=14; renewals.poll-cron=0 0 2 * * *; renewals.poll-zone=Europe/Moscow; holds.poll-window-hours=48; holds.poll-cron=0 15/30 * * * *; offers.poll-pause-ms=250; offers.poll-cron=0 30 2 * * *" \
    "YAML статьи разобран загрузчиком Boot: числа и три расписания"
expect_line "$ctx" "yaml статьи в контексте: daysBefore=7, pollWindowDays=14, pollWindowHours=48, задачи [0 0 2 * * *]" \
    "YAML статьи в контексте: настройки заполнены, обход продлений — 0 0 2 * * *"
expect_line_with "$ctx" "yaml кавычки-минус:" "renewals.poll-cron=-;" "poll-cron: \"-\" в кавычках — строка «-»"
expect_line_with "$ctx" "yaml минус: не разобрался" "sequence entries are not allowed here" \
    "⚠️ poll-cron: - без кавычек — начало списка, файл не разобрался"
expect_line_with "$ctx" "yaml звёздочка: не разобрался" "while scanning an alias" \
    "⚠️ */10 * * * * * без кавычек — разметка YAML, файл не разобрался"
expect_line_with "$ctx" "yaml без-кавычек:" "renewals.poll-cron=0 0 2 * * *;" \
    "0 0 2 * * * без кавычек YAML прочёл бы — кавычки здесь привычка"
show "$(sed -E 's/(не поднялся|не разобрался): (.{0,240}).*/\1: \2…/' <<<"$mine")"

section "javac: расписание из объекта настроек и sleep без catch не компилируются"
mkdir -p "$PROBE/javac/src" "$PROBE/javac/classes"
cat >"$PROBE/javac/src/CronFromSettings.java" <<'EOF'
import org.springframework.scheduling.annotation.Scheduled;

// Проба: расписание из объекта настроек в атрибуте аннотации — не компилируется.
class CronFromSettings {

    static class Settings {
        String getPollCron() {
            return "0 0 2 * * *";
        }
    }

    static final Settings props = new Settings();

    @Scheduled(cron = props.getPollCron())
    void poll() {
    }
}
EOF
cat >"$PROBE/javac/src/SleepWithoutCatch.java" <<'EOF'
// Проба: Thread.sleep без catch и без throws — не компилируется: InterruptedException проверяемое.
class SleepWithoutCatch {

    void pause() {
        Thread.sleep(250);
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/javac/classes" -cp "$TEST_DEPS" \
    "$PROBE/javac/src/CronFromSettings.java" 2>&1); code=$?
expect_failed "$code" "cron = props.getPollCron()"
expect_regex "$out" 'expression not allowed as annotation value|element value must be a constant expression' \
    "…значение атрибута аннотации нужно знать при компиляции"
show "$(head -n 4 <<<"$out")"
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/javac/classes" "$PROBE/javac/src/SleepWithoutCatch.java" 2>&1); code=$?
expect_failed "$code" "Thread.sleep без catch и throws"
expect_regex "$out" 'unreported exception (java\.lang\.)?InterruptedException; must be caught or declared to be thrown' \
    "InterruptedException проверяемое: поймать или объявить в throws требует компилятор"
show "$(head -n 4 <<<"$out")"

section "Что будет, если: без «не раньше сейчас» — return point;"
if variant no-clamp 's/return point\.isBefore\(now\) \? now : point;/return point;/' \
    "remindAt возвращает точку, даже прошедшую"; then
    expect_failed "$CODE" "без «не раньше сейчас»: ReminderPointTest"
    expect_summary "$OUT" 2 0 "без «не раньше сейчас»"
    expect_red_row "$OUT" 3 "красная строка 3 — точка прошла два часа назад…"
    expect_red_row "$OUT" 5 "…и строка 5 — секундой позже"
    expect_regex "$OUT" 'was: *<?"?2026-10-04T21:00:00Z' "…срок задачи остался в прошлом: 05.10 00:00 по Москве"
    for n in 1 2 4; do expect_green_row "$OUT" "$n" "строка $n зелёная"; done
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: «сейчас» из настоящих часов — Instant.now()"
today=$(date -u +%F)
if [[ "$today" < "2026-10-12" ]]; then
    note "сегодня $today: 12 октября 2026 ещё не прошло — мутация не показательна, пропущена"
elif variant instant-now 's/Instant now = clock\.instant\(\);/Instant now = Instant.now();/' \
    "Instant now = Instant.now();"; then
    expect_failed "$CODE" "Instant.now(): ReminderPointTest"
    expect_summary "$OUT" 5 0 "Instant.now() — сегодня $today"
    for n in 1 2 3 4 5; do expect_red_row "$OUT" "$n" "красная строка $n"; done
    expect_green "$OUT" rejectsMissingClock "rejectsMissingClock зелёный"
    show "$(red_detail "$OUT")"
    guard=$(java "${UTF8[@]}" -cp "$PROBE_CP" example.gameday.journal.ReminderProbe guard "$MUTANT/$POINT" 2>&1)
    expect_line "$guard" "сторож: ReminderPoint.java → 1" \
        "правило сторожа статьи 11 этот Instant.now() нашло бы — но в example.crm сторож не смотрит"
fi

section "Что будет, если: сравнение наоборот — isAfter вместо isBefore"
if variant is-after 's/point\.isBefore\(now\)/point.isAfter(now)/' "point.isAfter(now)"; then
    expect_failed "$CODE" "isAfter: ReminderPointTest"
    expect_summary "$OUT" 4 0 "isAfter"
    for n in 1 2 3 5; do expect_red_row "$OUT" "$n" "красная строка $n"; done
    expect_green_row "$OUT" 4 "зелёная только граница: обе ветки дают одно"
    expect_regex "$OUT" 'was: *<?"?2026-09-27T23:00:00Z' "строка 1: вместо точки — «сейчас», 28.09 02:00 по Москве"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: точка на секунду позже — граница ловит сдвиг вперёд"
if variant plus-second 's/until\.minus\(before\);/until.minus(before).plusSeconds(1);/' \
    "until.minus(before).plusSeconds(1)"; then
    expect_failed "$CODE" "на секунду позже: ReminderPointTest"
    expect_summary "$OUT" 3 0 "на секунду позже"
    for n in 1 2 4; do expect_red_row "$OUT" "$n" "красная строка $n"; done
    for n in 3 5; do expect_green_row "$OUT" "$n" "строка $n зелёная"; done
    expect_regex "$OUT" 'was: *<?"?2026-10-04T21:00:01Z' "на границе точка съехала вперёд на секунду"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: точка на секунду раньше — граница сдвиг назад не ловит"
if variant minus-second 's/until\.minus\(before\);/until.minus(before).minusSeconds(1);/' \
    "until.minus(before).minusSeconds(1)"; then
    expect_failed "$CODE" "на секунду раньше: ReminderPointTest"
    expect_summary "$OUT" 2 0 "на секунду раньше"
    for n in 1 2; do expect_red_row "$OUT" "$n" "красная строка $n"; done
    for n in 3 4 5; do expect_green_row "$OUT" "$n" "строка $n зелёная"; done
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: daysBefore < 0 вместо daysBefore < 1"
if variant below-zero 's/daysBefore < 1/daysBefore < 0/' "if (daysBefore < 0)"; then
    expect_failed "$CODE" "daysBefore < 0: ReminderPointTest"
    expect_summary "$OUT" 1 0 "daysBefore < 0"
    if red_lines "$OUT" | LC_ALL=C.UTF-8 grep -qE 'за "?0"? дн\. — ошибка'; then pass "красная строка «за 0 дн.»"
    else fail "строка «за 0 дн.» не красная"; fi
    expect_regex "$OUT" 'за "?-7"? дн\. — ошибка ✔' "«за -7 дн.» зелёная"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без Objects.requireNonNull"
if variant no-require 's/Objects\.requireNonNull\(clock, "часы не заданы"\)/clock/' "this.clock = clock;"; then
    expect_failed "$CODE" "без requireNonNull: ReminderPointTest"
    expect_summary "$OUT" 1 0 "без requireNonNull"
    expect_red "$OUT" rejectsMissingClock "красный rejectsMissingClock"
    show "$(red_detail "$OUT")"
fi

section "Первоисточники открываются"
for link in https://docs.spring.io/spring-framework/reference/integration/scheduling.html \
    https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/annotation/Scheduled.html \
    https://docs.spring.io/spring-boot/reference/features/external-config.html \
    https://www.iana.org/time-zones \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Thread.html; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
