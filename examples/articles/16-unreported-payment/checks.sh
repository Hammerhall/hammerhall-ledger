# Статья 16 «Оплата, о которой никто не сообщил» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 15: журнал в example.gameday.journal (18 файлов, 2 миграции), сторожа GameDayRulesTest
# (43 запуска), модель статей 12–15 в example.crm и её тесты. Код статьи — чистая Java: HeldPlace, OpenFollowUp
# и PaidSweep в src/main/java/example/crm, PaidSweepTest в src/test/java/example/crm. В mvn verify он уже прошёл.
# Здесь — то, что статья обещает словами: 13 запусков теста и прежние числа у тестов 12–15 и сторожа; код без Spring
# рядом с корнем пакетов, короткие куски части 4 — те же, что в «Пример целиком»; моменты, окно и полоса закрытия
# по Москве, края, «пустой ответ вместо сбоя», место без срока, «в момент запроса» и ошибки конструктора — на самой
# модели; текст задачи — шаблоном из статьи, Rubles и поясом Москвы; миллисекунда допуска — кусок части 3 как есть,
# плюс округление вверх; часы JDK; округление TIMESTAMPTZ — SQL статьи в Postgres на минуту; «что будет, если» —
# мутации PaidSweep: какая строка таблицы краснеет; первоисточники открываются. Мутации гоняются ConsoleLauncher
# JUnit той же версии, что в BOM Boot, — как в 12–15.

CLS=example.crm.PaidSweepTest
CRM=src/main/java/example/crm
CRM_TEST=src/test/java/example/crm
SWEEP=$CRM/PaidSweep.java
SWEEP_TEST=$CRM_TEST/PaidSweepTest.java
HERE=$PWD
ARTICLE=${ROOT:-}/articles/16-unreported-payment.md

# Строки таблицы closesOnlyInsideWindowWithMargin: минуты от запроса, закрыть ли — как в статье.
ROWS='-2940 false
-2850 false
-2820 true
-600 true
1245 true
2820 true
2850 false'

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
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 24; }

# Тест красный / зелёный в дереве. Аргументы: вывод, имя метода, пояснение.
expect_red()   { if red_lines "$1" | grep -qF -- "$2()"; then pass "$3"; else fail "$3: $2 не красный"; fi; }
expect_green() { if grep -qF -- "$2() ✔" <<<"$1"; then pass "$3"; else fail "$3: $2 не зелёный"; fi; }

# Подпись строки таблицы в дереве — «срок "-2940" мин от запроса → закрыть: "false"»; кавычки вокруг аргументов
# JUnit ставит сам, здесь они необязательны. Аргумент: минуты из первого столбца таблицы.
row_re() {
    local closed
    closed=$(awk -v m="$1" '$1 == m { print $2 }' <<<"$ROWS")
    printf 'срок "?%s"? мин от запроса → закрыть: "?%s"?' "$1" "$closed"
}

# Строка таблицы красная / зелёная. Аргументы: вывод, минуты, пояснение.
expect_red_row() {
    if red_lines "$1" | LC_ALL=C.UTF-8 grep -qE -- "$(row_re "$2")"; then pass "$3"; else fail "$3: строка $2 не красная"; fi
}
expect_green_row() {
    if LC_ALL=C.UTF-8 grep -qE -- "$(row_re "$2") ✔" <<<"$1"; then pass "$3"; else fail "$3: строка $2 не зелёная"; fi
}

# Строки @ValueSource: красная / зелёная по регулярному выражению подписи. Аргументы: вывод, выражение, пояснение.
expect_red_re()   { if red_lines "$1" | LC_ALL=C.UTF-8 grep -qE -- "$2"; then pass "$3"; else fail "$3: не красная"; fi; }
expect_green_re() { if LC_ALL=C.UTF-8 grep -qE -- "$2 ✔" <<<"$1"; then pass "$3"; else fail "$3: не зелёная"; fi; }
AT0='заведена через "?0"? с после запроса — не трогать'
AT2='заведена через "?2"? с после запроса — не трогать'
W23='окно "?23"? ч — ошибка'
W49='окно "?49"? ч — ошибка'

# Правка варианта должна что-то поменять. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    return 0
}

# Собрать код example.crm и тест статьи в $1/classes — без target/classes песочницы.
compile_crm() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$CRM"/*.java "$1/$SWEEP_TEST" >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): example.crm не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# PaidSweepTest в ConsoleLauncher на классах из $1.
crm_test() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" --select-class "$CLS" 2>&1
}

# Вариант: правка PaidSweep (perl), сборка, прогон теста. Вывод — в $OUT, код выхода — в $CODE, папка — в $MUTANT.
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
    perl "$flags" -e "$edit" "$v/$SWEEP"
    expect_changed "$v/$SWEEP" "$SWEEP" "$what" || return 1
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

# Каждая непустая строка куска статьи есть в файле. Аргументы: кусок, файл, пояснение.
expect_lines_in() {
    local missing
    missing=$(grep -v '^$' <<<"$1" | grep -vxF -f "$2")
    if [ -n "$1" ] && [ -z "$missing" ]; then pass "$3"; else fail "$3: строк нет в файле"; show "$missing"; fi
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CLS" 13
note "13 запусков PaidSweepTest: два теста, семь строк таблицы, две «заведена не раньше запроса», две «окно — ошибка»"
suite_ok example.crm.ReminderPointTest 8
suite_ok example.crm.CheckoutTest 11
suite_ok example.crm.RublesTest 5
suite_ok example.crm.FunnelNumbersTest 13
suite_ok example.crm.TodayListTest 3
suite_ok example.gameday.journal.GameDayRulesTest 43
note "у сторожа статьи 11 по-прежнему 43 запуска: в папку журнала новые классы не попали, миграций не прибавилось"
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
src=$(cat "$CRM/HeldPlace.java" "$CRM/OpenFollowUp.java" "$SWEEP")
expect_not_contains "$src" "org.springframework" "в HeldPlace, OpenFollowUp и PaidSweep нет ни одного импорта Spring"
expect_not_contains "$src" "@Component" "…и ни одной аннотации компонента"
expect_regex "$(grep -c '^package example.crm;$' <<<"$src")" '^3$' "все три — в example.crm, рядом с корнем example.gameday"
for file in FollowUp TodayList OrdinalDemo FunnelNumbers Discount PriceBreakdown Checkout Rubles ReminderPoint; do
    expect_file "$CRM/$file.java"
done
expect_regex "$(find src/main/java/example/gameday/journal -name '*.java' | grep -c '')" '^18$' \
    "в папке журнала по-прежнему 18 файлов — их и обходит сторож статьи 11"
expect_regex "$(find src/main/resources/db/migration -name '*.sql' | grep -c '')" '^2$' \
    "миграций по-прежнему две: миграция учебной CRM — для чтения"
expect_regex "$(grep -rlE 'HoldRow|closePaid|holdNote' src | grep -c '')" '^0$' "куски учебной CRM в песочницу не попали"
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    short=$(article_block "\`PaidSweep\` — сама сверка:" java)
    expect_contains "$short" "public List<OpenFollowUp> paid(" "в части 4 — короткий paid"
    expect_lines_in "$short" "$SWEEP" "каждая строка короткого paid — в PaidSweep «Пример целиком»"
    short=$(article_block "Главный тест — таблица из части 2" java)
    expect_contains "$short" "void closesOnlyInsideWindowWithMargin" "в части 4 — таблица теста"
    expect_lines_in "$short" "$SWEEP_TEST" "каждая строка таблицы теста в тексте — в PaidSweepTest «Пример целиком»"
fi
out=$(crm_test "$HERE/target/test-classes:$HERE/target/classes"); code=$?
expect_ok "$code" "ConsoleLauncher: PaidSweepTest на песочнице"
expect_summary "$out" 0 0 "PaidSweepTest"
expect_regex "$(summary_of "$out" 'tests successful')" '^13$' "зелёных 13"
while read -r minutes _; do expect_green_row "$out" "$minutes" "строка $minutes таблицы зелёная"; done <<<"$ROWS"
expect_green_re "$out" "$AT0" "строка «заведена через 0 с» зелёная"
expect_green_re "$out" "$AT2" "строка «заведена через 2 с» зелёная"
expect_green_re "$out" "$W23" "строка «окно 23 ч — ошибка» зелёная"
expect_green_re "$out" "$W49" "строка «окно 49 ч — ошибка» зелёная"
show "$(grep -E '✔|✘' <<<"$out" | grep -vE 'JUnit|PaidSweepTest ')"

section "Моменты, окно, полоса закрытия и текст задачи — на самой модели"
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/SweepProbe.java" <<'EOF'
package example.crm;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Проба для checks.sh статьи 16: печатает то, что статья обещает словами, — на самой PaidSweep и на java.time.
// В статью не идёт. Пакет — example.crm: EDGE виден только из него.
public class SweepProbe {

    static final ZoneId MSK = ZoneId.of("Europe/Moscow");
    static final DateTimeFormatter DAY_TIME = DateTimeFormatter.ofPattern("dd.MM HH:mm").withZone(MSK);
    static final UUID ONE = UUID.fromString("00000000-0000-4000-8000-000000000001");
    static final UUID TWO = UUID.fromString("00000000-0000-4000-8000-000000000002");
    static final UUID GROUP = UUID.fromString("00000000-0000-4000-8000-000000000100");

    public static void main(String[] args) throws Exception {
        // Моменты — прямо из PaidSweepTest.java (args[0]): текст статьи сверяется с данными теста.
        String test = Files.readString(Path.of(args[0]));
        Instant asked = constant(test, "ASKED_AT");
        Instant created = constant(test, "CREATED");
        Instant heldUntil = constant(test, "HELD_UNTIL");
        System.out.println("сверка: " + asked.atZone(MSK).getDayOfWeek() + " " + DAY_TIME.format(asked));
        System.out.println("задачу завели: " + DAY_TIME.format(created) + ", бронь до: " + DAY_TIME.format(heldUntil)
                + " (" + heldUntil.atZone(MSK).getDayOfWeek() + ")");
        System.out.println("бронь держится сутки с 11:00: " + DAY_TIME.format(heldUntil.minus(Duration.ofDays(1))));
        System.out.println("EDGE: " + PaidSweep.EDGE);
        PaidSweep sweep = new PaidSweep(Duration.ofHours(48));
        // Строки таблицы теста: что сделает модель и в какую полосу таблицы части 2 попадает срок.
        Matcher m = Pattern.compile("(?m)^\\s*(-?\\d+)\\s*\\|\\s*(true|false)\\s*$").matcher(test);
        int rows = 0;
        while (m.find()) {
            rows++;
            long minutes = Long.parseLong(m.group(1));
            Instant until = asked.plus(Duration.ofMinutes(minutes));
            boolean closed = closes(sweep, asked, until, created);
            System.out.println("строка " + minutes + ": " + band(Duration.ofMinutes(minutes)) + ", модель закрывает: "
                    + closed + ", ожидание: " + m.group(2));
        }
        System.out.println("строк в таблице теста: " + rows);
        System.out.println("1245 мин — срок брони: " + asked.plus(Duration.ofMinutes(1245)).equals(heldUntil));
        Instant from = asked.minus(Duration.ofHours(47));
        Instant to = asked.plus(Duration.ofHours(47));
        System.out.println("полоса закрытия по Москве: " + DAY_TIME.format(from) + " … " + DAY_TIME.format(to));
        // Края таблицы части 2.
        Instant[] edges = {asked.minus(Duration.ofHours(48)), from.minusNanos(1), from, to, to.plusNanos(1),
            asked.plus(Duration.ofHours(48))};
        String[] names = {"−48 ч", "−47 ч без 1 нс", "−47 ч", "+47 ч", "+47 ч и 1 нс", "+48 ч"};
        for (int i = 0; i < edges.length; i++) {
            System.out.println("край " + names[i] + ": закрыть " + closes(sweep, asked, edges[i], created));
        }
        // Живая бронь сгорает не позже чем через сутки — её срок в середине окна.
        boolean alive = true;
        for (int h = 0; h <= 24; h++) {
            alive &= closes(sweep, asked, asked.plus(Duration.ofHours(h)), created);
        }
        System.out.println("живая бронь, срок от 0 до +24 ч: всегда в полосе закрытия — " + alive);
        // Пустой список вместо сбоя: закрылось бы всё в окне.
        List<OpenFollowUp> open = new ArrayList<>();
        for (long h : new long[] {-47, -10, 0, 21, 47}) {
            open.add(new OpenFollowUp(open.size() + 1, ONE, GROUP, asked.plus(Duration.ofHours(h)), created));
        }
        System.out.println("пустой ответ вместо сбоя: закрыто " + sweep.paid(List.of(), asked, open).size()
                + " из " + open.size() + " задач в окне");
        // Сгоревшая больше окна назад: строки нет и без оплаты — не трогать.
        System.out.println("сгоревшая 49 ч назад, строки нет: закрыть "
                + closes(sweep, asked, asked.minus(Duration.ofHours(49)), created));
        // Место сроком не различается: в ответе то же место с новым сроком — задачу не трогать.
        OpenFollowUp task = new OpenFollowUp(1, ONE, GROUP, heldUntil, created);
        HeldPlace again = new HeldPlace(ONE, GROUP, heldUntil.plus(Duration.ofDays(2)));
        System.out.println("то же место с другим сроком в ответе: закрыть "
                + !sweep.paid(List.of(again), asked, List.of(task)).isEmpty());
        HeldPlace other = new HeldPlace(TWO, GROUP, heldUntil);
        System.out.println("в ответе только чужое место в той же группе: закрыть "
                + !sweep.paid(List.of(other), asked, List.of(task)).isEmpty());
        // Задача моложе запроса.
        System.out.println("заведена в момент запроса: закрыть " + closes(sweep, asked, heldUntil, asked));
        System.out.println("заведена за 1 нс до запроса: закрыть " + closes(sweep, asked, heldUntil, asked.minusNanos(1)));
        // Окно — от суток до двух.
        for (long h : new long[] {23, 24, 48, 49}) {
            try {
                new PaidSweep(Duration.ofHours(h));
                System.out.println("окно " + h + " ч: создано");
            } catch (IllegalArgumentException e) {
                System.out.println("окно " + h + " ч: " + e.getMessage());
            }
        }
        // Текст задачи: шаблон — из статьи (args[1]), срок — по Москве, цена — Rubles.
        DateTimeFormatter moment = DateTimeFormatter.ofPattern("dd.MM HH:mm xxx");
        System.out.println("срок по Москве: " + moment.format(heldUntil.atZone(MSK)) + ", как есть: " + heldUntil);
        System.out.println("цена: " + Rubles.format(480_000));
        System.out.println("текст: " + args[1].formatted("Утренняя йога", moment.format(heldUntil.atZone(MSK)),
                Rubles.format(480_000)));
        // Округление вверх: в базе .123457, в ответе .123456789; вторая ветка правила 1 — «бронь сгорела».
        Instant base = Instant.parse("2026-10-06T08:00:00.123457Z");
        Instant club = Instant.parse("2026-10-06T08:00:00.123456789Z");
        System.out.println("вверх, строго: «бронь сгорела» закроет " + !club.isBefore(base));
        System.out.println("вверх, с допуском: «бронь сгорела» закроет " + !club.plus(Duration.ofMillis(1)).isBefore(base)
                + ", «занято снова» закроет " + base.plus(Duration.ofMillis(1)).isBefore(club));
        System.out.println("1 мс в 2000 раз больше 0,5 мкс: " + (Duration.ofMillis(1).dividedBy(Duration.ofNanos(500)) == 2000)
                + "; в шестьдесят тысяч раз меньше минуты: "
                + (Duration.ofMinutes(1).dividedBy(Duration.ofMillis(1)) == 60 * 1000));
        // Часы JDK: сколько знаков после точки настоящие.
        Clock clock = Clock.systemUTC();
        int notMicro = 0;
        for (int i = 0; i < 100_000; i++) {
            if (clock.instant().getNano() % 1000 != 0) {
                notMicro++;
            }
        }
        System.out.println("Instant.now() = " + Instant.now());
        System.out.println("из 100000 замеров не кратны микросекунде: " + notMicro);
        System.out.println("--- конец");
    }

    static Instant constant(String test, String name) {
        Matcher m = Pattern.compile(name + " = Instant\\.parse\\(\"([^\"]+)\"\\)").matcher(test);
        if (!m.find()) {
            throw new IllegalStateException("в тесте нет " + name);
        }
        return Instant.parse(m.group(1));
    }

    static boolean closes(PaidSweep sweep, Instant asked, Instant until, Instant created) {
        return !sweep.paid(List.of(), asked, List.of(new OpenFollowUp(1, ONE, GROUP, until, created))).isEmpty();
    }

    /** Полоса таблицы части 2 по сроку относительно запроса. */
    static String band(Duration d) {
        Duration h47 = Duration.ofHours(47);
        Duration h48 = Duration.ofHours(48);
        if (d.compareTo(h48.negated()) < 0) {
            return "срок < −48 ч";
        } else if (d.compareTo(h47.negated()) < 0) {
            return "−48 ч ≤ срок < −47 ч";
        } else if (d.compareTo(h47) <= 0) {
            return "−47 ч ≤ срок ≤ +47 ч";
        } else if (d.compareTo(h48) <= 0) {
            return "+47 ч < срок ≤ +48 ч";
        }
        return "срок > +48 ч";
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "target/classes" "$PROBE/src/SweepProbe.java" 2>&1)
expect_ok $? "javac пробы модели"
show "$out"
TEMPLATE=""
if [ -f "$ARTICLE" ]; then
    TEMPLATE=$(sed -nE 's/^ *return "(Бронь в группе .*)"$/\1/p' "$ARTICLE")
    expect_regex "$(grep -c '' <<<"$TEMPLATE")" '^1$' "в статье один шаблон текста задачи — в holdNote"
fi
probe=$(java "${UTF8[@]}" -cp "$PROBE/classes:target/classes" example.crm.SweepProbe "$SWEEP_TEST" "$TEMPLATE" 2>&1)
expect_contains "$probe" "--- конец" "проба модели дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"
expect_line "$probe" "сверка: MONDAY 05.10 14:15" "сверка — понедельник, 5 октября, 14:15 по Москве"
expect_line "$probe" "задачу завели: 05.10 11:15, бронь до: 06.10 11:00 (TUESDAY)" \
    "задачу завёл опрос в 11:15; бронь — до 11:00 вторника, та же, что в статье 12"
expect_line "$probe" "бронь держится сутки с 11:00: 05.10 11:00" "забронировал в 11:00 — бронь держится сутки"
expect_line "$probe" "EDGE: PT1H" "запас — час"
expect_line "$probe" "строк в таблице теста: 7" "в таблице теста семь строк"
expect_regex "$(grep -c '^строка .*модель закрывает: \(true, ожидание: true\|false, ожидание: false\)$' <<<"$probe")" '^7$' \
    "ожидания всех семи строк — то, что даёт модель"
expect_line "$probe" "строка -2940: срок < −48 ч, модель закрывает: false, ожидание: false" "−2940 — за окном"
expect_line "$probe" "строка -2850: −48 ч ≤ срок < −47 ч, модель закрывает: false, ожидание: false" "−2850 — в полосе запаса"
expect_line "$probe" "строка -2820: −47 ч ≤ срок ≤ +47 ч, модель закрывает: true, ожидание: true" \
    "−2820 — ровно −47 ч, край запаса, включительно"
expect_line "$probe" "строка 2850: +47 ч < срок ≤ +48 ч, модель закрывает: false, ожидание: false" "2850 — в полосе запаса"
expect_line "$probe" "1245 мин — срок брони: true" "1245 минут от запроса — 06.10 11:00 по Москве, бронь из начала статьи"
expect_line "$probe" "полоса закрытия по Москве: 03.10 15:15 … 07.10 13:15" "закрыть можно сроки от 03.10 15:15 до 07.10 13:15"
for edge in "−48 ч: закрыть false" "−47 ч без 1 нс: закрыть false" "−47 ч: закрыть true" "+47 ч: закрыть true" \
    "+47 ч и 1 нс: закрыть false" "+48 ч: закрыть false"; do
    expect_line "$probe" "край $edge" "таблица части 2, край $edge"
done
expect_line "$probe" "живая бронь, срок от 0 до +24 ч: всегда в полосе закрытия — true" "живая бронь — всегда в середине окна"
expect_line "$probe" "пустой ответ вместо сбоя: закрыто 5 из 5 задач в окне" \
    "🔴 пустой список вместо сбоя закрыл бы все задачи в окне"
expect_line "$probe" "сгоревшая 49 ч назад, строки нет: закрыть false" "выпавшую из окна сверка не трогает"
expect_line "$probe" "то же место с другим сроком в ответе: закрыть false" "место — человек в группе, сроком не различается"
expect_line "$probe" "в ответе только чужое место в той же группе: закрыть true" "чужое место в той же группе — не наше"
expect_line "$probe" "заведена в момент запроса: закрыть false" "заведена в момент запроса — не трогать"
expect_line "$probe" "заведена за 1 нс до запроса: закрыть true" "…а на наносекунду раньше — уже старше запроса"
expect_line "$probe" "окно 23 ч: окно — от суток до двух, а пришло PT23H" "окно 23 ч — ошибка с текстом"
expect_line "$probe" "окно 24 ч: создано" "окно 24 ч — можно"
expect_line "$probe" "окно 48 ч: создано" "окно 48 ч — можно"
expect_line "$probe" "окно 49 ч: окно — от суток до двух, а пришло PT49H" "окно 49 ч — ошибка с текстом"
expect_line "$probe" "срок по Москве: 06.10 11:00 +03:00, как есть: 2026-10-06T08:00:00Z" \
    "срок брони по Москве — 06.10 11:00 +03:00; как есть — «до восьми утра»"
expect_line "$probe" "цена: 4 800 ₽" "Rubles.format(480_000) — «4 800 ₽»"
if [ -f "$ARTICLE" ]; then
    text=$(awk '/^задачу:$/ { on = 1; next } on && /^```$/ { if (inside) exit; inside = 1; next } inside { print }' "$ARTICLE")
    expect_line "$probe" "текст: $text" "текст задачи в начале статьи — шаблон holdNote, срок по Москве и Rubles"
fi
expect_line "$probe" "вверх, строго: «бронь сгорела» закроет false" \
    "округлись срок вверх — строгое сравнение оставило бы живую задачу открытой"
expect_line "$probe" "вверх, с допуском: «бронь сгорела» закроет true, «занято снова» закроет false" \
    "…с допуском закрывается «бронь сгорела», и только она"
expect_line "$probe" "1 мс в 2000 раз больше 0,5 мкс: true; в шестьдесят тысяч раз меньше минуты: true" \
    "допуск в 2 000 раз больше полмикросекунды и в шестьдесят тысяч раз меньше минуты"
show "$(grep -vE '^(строка -?[0-9]+:|--- конец)' <<<"$probe")"
not_micro=$(sed -nE 's/^из 100000 замеров не кратны микросекунде: ([0-9]+)$/\1/p' <<<"$probe")
if [ "${not_micro:-0}" -gt 0 ]; then
    pass "часы JDK на этой машине дают больше шести знаков: не кратны микросекунде $not_micro из 100 000"
else
    note "часы этой машины дали только микросекунды — «сколько знаков настоящих, решают системные часы»"
fi

section "Миллисекунда допуска — кусок части 3 как есть"
if [ -f "$ARTICLE" ]; then
    snippet=$(awk '/^```java$/ { inside = 1; buf = ""; next }
        inside && /^```$/ { inside = 0; if (buf ~ /Instant fromClub/) { printf "%s", buf; exit } next }
        inside { buf = buf $0 "\n" }' "$ARTICLE")
    expect_regex "$(grep -c '' <<<"$snippet")" '^4$' "в части 3 — четыре строки про fromClub и fromBase"
    mkdir -p "$PROBE/snippet/classes"
    {
        echo "import java.time.Duration;"
        echo "import java.time.Instant;"
        echo "public class SnippetRun {"
        echo "    public static void main(String[] args) {"
        # Выражение без присваивания — напечатать с тем, что обещает комментарий статьи.
        perl -pe 's{^(fromBase\S.*?);\s*//\s*(true|false)\b.*$}{System.out.println("$2 " + ($1));}' <<<"$snippet"
        echo "    }"
        echo "}"
    } >"$PROBE/snippet/SnippetRun.java"
    out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/snippet/classes" "$PROBE/snippet/SnippetRun.java" 2>&1)
    expect_ok $? "кусок статьи компилируется как есть"
    show "$out"
    out=$(java "${UTF8[@]}" -cp "$PROBE/snippet/classes" SnippetRun 2>&1)
    expect_regex "$(grep -c '' <<<"$out")" '^2$' "кусок печатает два сравнения"
    expect_line "$out" "true true" "fromBase.isBefore(fromClub) — true: строго «раньше» на 289 нс"
    expect_line "$out" "false false" "с Duration.ofMillis(1) — false: один срок"
    show "$out"
fi

section "Округление TIMESTAMPTZ — SQL части 3 в Postgres на минуту"
DB=game-day-db
IMAGE=postgres:17-alpine
db_down() { docker rm -f "$DB" >/dev/null 2>&1; return 0; }
psql_in() { docker exec -i "$DB" psql -X -U postgres 2>&1; }
db_ok=0
sql=""
if [ -f "$ARTICLE" ]; then
    sql=$(awk '/^```sql$/ { inside = 1; buf = ""; next }
        inside && /^```$/ { inside = 0; if (buf ~ /::timestamptz/) { printf "%s", buf; exit } next }
        inside { buf = buf $0 "\n" }' "$ARTICLE")
    expect_regex "$(grep -c '::timestamptz' <<<"$sql")" '^2$' "в части 3 — два SELECT с ::timestamptz"
    trap db_down EXIT
    db_down
    if docker run -d --rm --name "$DB" -e POSTGRES_PASSWORD=game-day-local "$IMAGE" >/dev/null; then
        for ((i = 0; i < 90; i++)); do
            if docker exec "$DB" pg_isready -q -h 127.0.0.1 -U postgres; then db_ok=1; break; fi
            sleep 1
        done
    fi
    if [ "$db_ok" -eq 1 ]; then pass "docker run $IMAGE: база принимает подключения"; else fail "база в контейнере не поднялась"; fi
fi
if [ "$db_ok" -eq 1 ]; then
    out=$(psql_in <<<"$sql")
    got=$(sed -nE 's/^ *([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+\+00) *$/\1/p' <<<"$out")
    expected=$(sed -nE 's/^SELECT .*-- (.*)$/\1/p' <<<"$sql")
    if [ -n "$got" ] && [ "$got" = "$expected" ]; then
        pass "ответы базы — как в комментариях статьи, по порядку: .123456789 → .123457, .123456289 → .123456"
    else
        fail "ответы базы не те, что в статье"
        show "$(printf 'в статье:\n%s\nбаза:\n%s' "$expected" "$got")"
    fi
    show "$out"
    db_down
fi

section "Что будет, если: без фильтра «места нет в ответе»"
# shellcheck disable=SC2016  # $_ — переменная perl, а не bash
if variant no-answer '$_ = "" if /\.filter\(task -> !inAnswer\.contains/' "без .filter(… !inAnswer.contains(…))"; then
    expect_failed "$CODE" "без «нет в ответе»: PaidSweepTest"
    expect_summary "$OUT" 1 0 "без «нет в ответе»"
    expect_red "$OUT" keepsTaskWhosePlaceIsInAnswer "красный keepsTaskWhosePlaceIsInAnswer…"
    expect_contains "$OUT" "id=2" "…закрыта и задача того, чьё место держится"
    expect_green "$OUT" closesTaskWhosePlaceIsMissingFromAnswer "closesTaskWhosePlaceIsMissingFromAnswer зелёный"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без фильтра окна"
# shellcheck disable=SC2016
if variant no-window '$_ = "" if /\.filter\(task -> !task\.untilAt\(\)\.isBefore\(from\)/' "без фильтра окна"; then
    expect_failed "$CODE" "без окна: PaidSweepTest"
    expect_summary "$OUT" 3 0 "без окна"
    for minutes in -2940 -2850 2850; do expect_red_row "$OUT" "$minutes" "красная строка $minutes"; done
    for minutes in -2820 -600 1245 2820; do expect_green_row "$OUT" "$minutes" "строка $minutes зелёная"; done
    expect_regex "$OUT" 'Expected size: *0 but was: *1' "закрыта задача, которую надо было не трогать"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: EDGE = Duration.ZERO — запаса нет"
if variant edge-zero 's/static final Duration EDGE = Duration\.ofHours\(1\);/static final Duration EDGE = Duration.ZERO;/' \
    "EDGE = Duration.ZERO"; then
    expect_failed "$CODE" "без запаса: PaidSweepTest"
    expect_summary "$OUT" 2 0 "без запаса"
    for minutes in -2850 2850; do expect_red_row "$OUT" "$minutes" "красная строка $minutes — полоса запаса"; done
    for minutes in -2940 -2820 -600 1245 2820; do expect_green_row "$OUT" "$minutes" "строка $minutes зелёная"; done
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: края строго — isAfter(from) && isBefore(to)"
if variant strict-edges \
    's/!task\.untilAt\(\)\.isBefore\(from\) && !task\.untilAt\(\)\.isAfter\(to\)/task.untilAt().isAfter(from) \&\& task.untilAt().isBefore(to)/' \
    "task.untilAt().isAfter(from) && task.untilAt().isBefore(to)"; then
    expect_failed "$CODE" "края строго: PaidSweepTest"
    expect_summary "$OUT" 2 0 "края строго"
    for minutes in -2820 2820; do expect_red_row "$OUT" "$minutes" "красная строка $minutes — край запаса"; done
    for minutes in -2940 -2850 -600 1245 2850; do expect_green_row "$OUT" "$minutes" "строка $minutes зелёная"; done
    expect_regex "$OUT" 'Expected size: *1 but was: *0' "край выпал: задача не закрыта"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без фильтра «до запроса»"
# shellcheck disable=SC2016
if variant no-before-ask '$_ = "" if /\.filter\(task -> task\.createdAt\(\)\.isBefore\(askedAt\)\)/' \
    "без .filter(task -> task.createdAt().isBefore(askedAt))"; then
    expect_failed "$CODE" "без «до запроса»: PaidSweepTest"
    expect_summary "$OUT" 2 0 "без «до запроса»"
    expect_red_re "$OUT" "$AT0" "красная строка «через 0 с»"
    expect_red_re "$OUT" "$AT2" "красная строка «через 2 с»"
    expect_contains "$OUT" "Expecting empty" "задача моложе запроса закрыта"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: !isAfter(askedAt) вместо isBefore(askedAt)"
if variant not-after 's/task\.createdAt\(\)\.isBefore\(askedAt\)/!task.createdAt().isAfter(askedAt)/' \
    "!task.createdAt().isAfter(askedAt)"; then
    expect_failed "$CODE" "!isAfter: PaidSweepTest"
    expect_summary "$OUT" 1 0 "!isAfter"
    expect_red_re "$OUT" "$AT0" "красная только «через 0 с»: заведённая в момент запроса уже не моложе"
    expect_green_re "$OUT" "$AT2" "«через 2 с» зелёная"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без проверки окна в конструкторе"
if variant no-window-check 's/\s*if \(window\.compareTo[^}]*\}\n//s' "PaidSweep без if (window.compareTo…)" -0pi; then
    expect_not_contains "$(cat "$MUTANT/$SWEEP")" "window.compareTo" "проверки в варианте нет"
    expect_failed "$CODE" "без проверки окна: PaidSweepTest"
    expect_summary "$OUT" 2 0 "без проверки окна"
    expect_red_re "$OUT" "$W23" "красная строка «окно 23 ч»"
    expect_red_re "$OUT" "$W49" "красная строка «окно 49 ч»"
    show "$(red_detail "$OUT")"
fi

section "Первоисточники открываются"
for link in https://www.postgresql.org/docs/current/datatype-datetime.html \
    https://bugs.openjdk.org/browse/JDK-8242504 \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Clock.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Instant.html; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
