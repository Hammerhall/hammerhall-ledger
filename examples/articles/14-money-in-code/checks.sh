# Статья 14 «Деньги в коде: копейки, скидки, округление» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 13: журнал в example.gameday.journal (18 файлов, 2 миграции), сторожа GameDayRulesTest
# (43 запуска), модель статей 12–13 в example.crm — FollowUp, TodayList, OrdinalDemo, FunnelNumbers и их тесты.
# Код статьи — чистая Java: Discount, PriceBreakdown, Checkout и Rubles в src/main/java/example/crm,
# CheckoutTest и RublesTest в src/test/java/example/crm. В mvn verify он уже прошёл. Здесь — то, что статья
# обещает словами: 11 и 5 запусков тестов, у сторожа статьи 11 по-прежнему 43; код без Spring рядом с корнем
# пакетов; числа и разборы статьи на самой модели (double и копейки, локали, BigDecimal, порядок скидок, каскад,
# округление, «скидка не больше цены», «разбор сходится», «ровно одно», даты акции); без типа в лямбде ORDER
# не собирается; «что будет, если» — мутации модели: какие строки таблицы краснеют и что приходит вместо
# ожидаемого; 💡 без if (given > 0) — всё зелёное; таблица скидок части 2 — в Postgres на минуту из статьи 3а
# (SQL берётся из текста статьи), ошибки и порядок строк без ORDER BY; первоисточники открываются.
# Мутации гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в статьях 11–13.

CHECKOUT_CLS=example.crm.CheckoutTest
RUBLES_CLS=example.crm.RublesTest
CRM=src/main/java/example/crm
CRM_TEST=src/test/java/example/crm
DISCOUNT=$CRM/Discount.java
CHECKOUT=$CRM/Checkout.java
RUBLES=$CRM/Rubles.java
CHECKOUT_TEST=$CRM_TEST/CheckoutTest.java
RUBLES_TEST=$CRM_TEST/RublesTest.java
HERE=$PWD
NBSP=$(printf '\302\240')   # U+00A0, неразрывный пробел — его ставит русская локаль

# Строки таблицы CheckoutTest: цена, скидки, итог — как в статье.
ROWS='101 50% 50
40000 50000 0
3000000 10%;50000 2650000
3000000 50000;10% 2650000
3000000 10%;15% 2295000
350000 30% 245000
350000 100%;10000 0'

# Строки таблицы RublesTest: копейки | как видит человек.
RUBLE_ROWS='3000000|30 000 ₽
2650050|26 500,50 ₽
40000|400 ₽
5|0,05 ₽'

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
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 20; }

# Тест красный / зелёный в дереве. Аргументы: вывод, имя метода, пояснение.
expect_red()   { if red_lines "$1" | grep -qF -- "$2()"; then pass "$3"; else fail "$3: $2 не красный"; fi; }
expect_green() { if grep -qF -- "$2() ✔" <<<"$1"; then pass "$3"; else fail "$3: $2 не зелёный"; fi; }

# Подпись строки таблицы CheckoutTest в дереве — «"101" коп., скидки "50%" → итог "50"» по
# name = "{0} коп., скидки {1} → итог {2}»; кавычки вокруг аргументов JUnit ставит сам, здесь они
# необязательны. Аргументы: цена, скидки, итог.
row_re() { printf '"?%s"? коп\\., скидки "?%s"? → итог "?%s"?' "$1" "$2" "$3"; }

# Подпись строки таблицы RublesTest — «"5" коп. → "0,05 ₽"». Аргументы: копейки, текст.
ruble_re() { printf '"?%s"? коп\\. → "?%s"?' "$1" "$2"; }

# Строка таблицы красная / зелёная. Аргументы: вывод, регулярное выражение подписи, пояснение.
expect_red_row() {
    if red_lines "$1" | LC_ALL=C.UTF-8 grep -qE -- "$2"; then pass "$3"; else fail "$3: строка не красная"; fi
}
expect_green_row() {
    if LC_ALL=C.UTF-8 grep -qE -- "$2 ✔" <<<"$1"; then pass "$3"; else fail "$3: строка не зелёная"; fi
}

# Правка варианта должна что-то поменять. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    return 0
}

# Собрать код example.crm и оба теста статьи в $1/classes — без target/classes песочницы.
compile_crm() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$CRM"/*.java "$1/$CHECKOUT_TEST" "$1/$RUBLES_TEST" >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): example.crm не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# Тест статьи в ConsoleLauncher на классах из $1. Аргументы: папка классов, класс теста.
crm_test() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" --select-class "$2" 2>&1
}

# Вариант: правка файла (perl), сборка, прогон теста. Вывод — в $OUT, код выхода — в $CODE, папка — в $MUTANT.
# Аргументы: имя варианта, файл, perl-правка, что правили, класс теста, флаги perl (необязательно).
OUT=""
CODE=0
MUTANT=""
variant() {
    local name=$1 file=$2 edit=$3 what=$4 cls=$5 flags=${6:--pi} v
    OUT=""
    CODE=0
    v=$(make_variant "$name")
    MUTANT=$v
    perl "$flags" -e "$edit" "$v/$file"
    expect_changed "$v/$file" "$file" "$what" || return 1
    pass "в варианте: $what"
    compile_crm "$v" || return 1
    OUT=$(crm_test "$v/classes" "$cls")
    CODE=$?
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CHECKOUT_CLS" 11
note "11 запусков CheckoutTest: семь строк таблицы и четыре теста"
suite_ok "$RUBLES_CLS" 5
note "5 запусков RublesTest: четыре строки и один тест"
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

section "Код статьи — чистая Java рядом с корнем пакетов; журнал и модели статей 12–13 на месте"
src=$(cat "$DISCOUNT" "$CRM/PriceBreakdown.java" "$CHECKOUT" "$RUBLES")
expect_not_contains "$src" "org.springframework" "в Discount, PriceBreakdown, Checkout и Rubles нет ни одного импорта Spring"
expect_not_contains "$src" "@Component" "…и ни одной аннотации компонента"
expect_contains "$src" "package example.crm;" "код статьи — в example.crm: рядом с корнем example.gameday, не внутри"
for file in FollowUp TodayList OrdinalDemo FunnelNumbers; do expect_file "$CRM/$file.java"; done
for file in TodayListTest FunnelNumbersTest; do expect_file "$CRM_TEST/$file.java"; done
expect_regex "$(find src/main/java/example/gameday/journal -name '*.java' | grep -c '')" '^18$' \
    "в папке журнала по-прежнему 18 файлов — их и обходит сторож статьи 11"
expect_regex "$(find src/main/resources/db/migration -name '*.sql' | grep -c '')" '^2$' \
    "миграций по-прежнему две: таблица скидок части 2 — SQL для psql, а не миграция журнала"
out=$(crm_test "$HERE/target/test-classes:$HERE/target/classes" "$CHECKOUT_CLS"); code=$?
expect_ok "$code" "ConsoleLauncher: CheckoutTest на песочнице"
expect_summary "$out" 0 0 "CheckoutTest"
expect_regex "$(summary_of "$out" 'tests successful')" '^11$' "зелёных 11: семь строк таблицы и четыре теста"
while read -r base discounts total; do
    expect_green_row "$out" "$(row_re "$base" "$discounts" "$total")" "таблица: $base коп., скидки $discounts → $total"
done <<<"$ROWS"
for test in orderChangesTheTotal roundsTotalDownNotDiscount breakdownShowsWhatWasReallyGiven \
    discountIsPercentOrAmountNotBoth; do
    expect_green "$out" "$test" "$test зелёный"
done
show "$(grep -E '✔|✘' <<<"$out" | grep -vE 'JUnit|CheckoutTest ')"
out=$(crm_test "$HERE/target/test-classes:$HERE/target/classes" "$RUBLES_CLS"); code=$?
expect_ok "$code" "ConsoleLauncher: RublesTest на песочнице"
expect_summary "$out" 0 0 "RublesTest"
expect_regex "$(summary_of "$out" 'tests successful')" '^5$' "зелёных 5: четыре строки и один тест"
while IFS='|' read -r minor text; do
    expect_green_row "$out" "$(ruble_re "$minor" "$text")" "RublesTest: $minor коп. → $text"
done <<<"$RUBLE_ROWS"
show "$(grep -E '✔|✘' <<<"$out" | grep -vE 'JUnit|RublesTest ')"

section "Числа и разборы статьи — на самой модели"
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/MoneyProbe.java" <<'EOF'
package example.crm;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Currency;
import java.util.List;
import java.util.Locale;
import java.util.Map;

// Проба для checks.sh статьи 14: печатает то, что статья обещает словами. В статью не идёт.
// Пакет — example.crm: ORDER и cascade видны только из него.
public class MoneyProbe {

    static final long VISIT = 40_000;
    static final long MONTH = 350_000;
    static final long YEAR = 3_000_000;

    public static void main(String[] args) {
        // часть 1: double и копейки
        System.out.println("0.1 + 0.2: " + (0.1 + 0.2));
        System.out.println("0.1 + 0.2 == 0.3: " + (0.1 + 0.2 == 0.3));
        System.out.println("1 из 3 в double: " + (1 * 100.0 / 3));
        System.out.println("1 из 3 на панели: " + new FunnelNumbers(3, Map.of("BECAME_MEMBER", 1L, "NEW", 2L))
                .shareOfAll("BECAME_MEMBER"));
        double price = 1.15;
        System.out.println("1.15 * 100: " + price * 100);
        System.out.println("(long) (1.15 * 100): " + (long) (price * 100));
        System.out.println("350_000 * 0.7: " + MONTH * 0.7);
        System.out.println("(long) (350_000 * 0.7): " + (long) (MONTH * 0.7));
        System.out.println("месяц −30 % в копейках: " + Checkout.price(MONTH, List.of(Discount.percent("m", 30)))
                .finalMinor());
        double sum = 0;
        for (int i = 0; i < 10; i++) {
            sum += 0.1;
        }
        System.out.println("десять раз по 0.1: " + sum);
        System.out.println("Integer.MAX_VALUE: " + Integer.MAX_VALUE);
        System.out.println("Long.MAX_VALUE больше 9·10¹⁸: " + (Long.MAX_VALUE > 9_000_000_000_000_000_000L));
        int max = Integer.MAX_VALUE;
        System.out.println("int: MAX_VALUE + 100 меньше нуля, без исключения: " + (max + 100 < 0));
        for (String code : List.of("RUB", "EUR", "JPY")) {
            System.out.println("младших разрядов у " + code + ": "
                    + Currency.getInstance(code).getDefaultFractionDigits());
        }
        // часть 1: рубли на экране
        for (long minor : List.of(3_000_000L, 2_650_050L, 40_000L, 5L)) {
            System.out.println("Rubles.format(" + minor + "): " + Rubles.format(minor));
        }
        try {
            Rubles.format(-1);
            System.out.println("Rubles.format(-1): строка");
        } catch (IllegalArgumentException e) {
            System.out.println("Rubles.format(-1): " + e.getMessage());
        }
        for (String tag : List.of("und", "de-DE", "de-CH", "ru-RU")) {
            Locale locale = Locale.forLanguageTag(tag);
            String text = String.format(locale, "%,d", 30_000);
            System.out.println("%,d 30000 в " + tag + ": " + text.replace(" ", "<U+00A0>"));
        }
        String russian = String.format(Locale.of("ru"), "%,d", 30_000);
        System.out.println("русская равна \"30 000\": " + russian.equals("30 000"));
        System.out.println("русская после замены U+00A0 на пробел равна \"30 000\": "
                + russian.replace(' ', ' ').equals("30 000"));
        // часть 1: BigDecimal
        System.out.println("new BigDecimal(0.1): " + new BigDecimal(0.1));
        System.out.println("new BigDecimal(\"0.1\"): " + new BigDecimal("0.1"));
        try {
            new BigDecimal("100").divide(new BigDecimal("3"));
            System.out.println("100 / 3 без округления: посчитано");
        } catch (ArithmeticException e) {
            System.out.println("100 / 3 без округления: " + e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        System.out.println("100 / 3, 2 знака, HALF_EVEN: "
                + new BigDecimal("100").divide(new BigDecimal("3"), 2, RoundingMode.HALF_EVEN));
        // часть 2: «ровно одно» и фабрики
        for (Object[] bad : new Object[][] {{"both", 10, 50_000L}, {"none", null, null}, {"zero", 0, null},
                {"too-much", 101, null}, {" ", 10, null}}) {
            try {
                new Discount((String) bad[0], (Integer) bad[1], (Long) bad[2]);
                System.out.println("скидка " + bad[0] + ": создана");
            } catch (IllegalArgumentException e) {
                System.out.println("скидка " + bad[0] + ": " + e.getMessage());
            }
        }
        System.out.println("100 %: " + Discount.percent("free-month", 100));
        System.out.println("percent(\"year-10\", 10) равна new Discount(\"year-10\", 10, null): "
                + Discount.percent("year-10", 10).equals(new Discount("year-10", 10, null)));
        Discount minus = Discount.amount("minus", -50_000);
        System.out.println("💡 скидка суммой −50 000 создана: " + minus);
        System.out.println("💡 её from(годовой): " + minus.from(YEAR));
        PriceBreakdown withMinus = Checkout.price(YEAR, List.of(minus));
        System.out.println("💡 годовой с ней: " + withMinus.finalMinor() + ", в разборе: " + withMinus.applied());
        // часть 2: даты акции «с 1 по 7 октября»
        LocalDate validFrom = LocalDate.of(2026, 10, 1);
        LocalDate validTo = LocalDate.of(2026, 10, 7);
        for (int day : List.of(30, 1, 7, 8)) {
            LocalDate today = day == 30 ? LocalDate.of(2026, 9, 30) : LocalDate.of(2026, 10, day);
            System.out.println("акция 01.10–07.10, " + today + ": " + active(today, validFrom, validTo)
                    + ", с isAfter(validFrom): " + (today.isAfter(validFrom) && !today.isAfter(validTo)));
        }
        System.out.println("без границ: " + active(LocalDate.of(2026, 10, 5), null, null));
        ZoneId moscow = ZoneId.of("Europe/Moscow");
        for (String moment : List.of("2026-10-07T20:59:00Z", "2026-10-07T21:00:00Z")) {
            LocalDate today = LocalDate.now(Clock.fixed(Instant.parse(moment), moscow));
            System.out.println("часы " + moment + " по Москве — " + today + ": " + active(today, validFrom, validTo));
        }
        // часть 3: порядок, каскад, округление
        Discount yearTen = Discount.percent("year-10", 10);
        Discount friend = Discount.amount("friend-500", 50_000);
        PriceBreakdown year = Checkout.price(YEAR, List.of(friend, yearTen));
        System.out.println("годовой, за годовой и за друга: " + year.applied() + " → " + year.finalMinor());
        System.out.println("процент → сумма: " + Checkout.cascade(YEAR, List.of(yearTen, friend)).finalMinor());
        System.out.println("сумма → процент: " + Checkout.cascade(YEAR, List.of(friend, yearTen)).applied()
                + " → " + Checkout.cascade(YEAR, List.of(friend, yearTen)).finalMinor());
        List<Discount> mixed = new ArrayList<>(List.of(Discount.amount("b-flat", 100), Discount.percent("z-pct", 5),
                Discount.amount("a-flat", 100), Discount.percent("a-pct", 5)));
        System.out.println("ORDER: " + mixed.stream().sorted(Checkout.ORDER).map(Discount::code).toList());
        Discount ten = Discount.percent("p10", 10);
        Discount fifteen = Discount.percent("p15", 15);
        PriceBreakdown twoPercents = Checkout.price(YEAR, List.of(fifteen, ten));
        long given = YEAR - twoPercents.finalMinor();
        System.out.println("10 % и 15 % на годовой: " + twoPercents.applied() + " → " + twoPercents.finalMinor()
                + ", всего " + given + ", " + BigDecimal.valueOf(given * 100).divide(BigDecimal.valueOf(YEAR))
                .stripTrailingZeros().toPlainString() + " %");
        System.out.println("271828, 10 % → 15 %: " + Checkout.cascade(271_828, List.of(ten, fifteen)).finalMinor());
        System.out.println("271828, 15 % → 10 %: " + Checkout.cascade(271_828, List.of(fifteen, ten)).finalMinor());
        PriceBreakdown half = Checkout.price(101, List.of(Discount.percent("half", 50)));
        System.out.println("101, −50 %: " + half.applied() + " → " + half.finalMinor());
        System.out.println("101, −50 %, если вниз скидку: скидка " + Math.floorDiv(101 * 50, 100)
                + ", итог " + (101 - Math.floorDiv(101 * 50, 100)));
        System.out.println("-7 / 2: " + (-7 / 2) + ", Math.floorDiv(-7, 2): " + Math.floorDiv(-7, 2)
                + ", 7 / 2: " + (7 / 2) + ", Math.floorDiv(7, 2): " + Math.floorDiv(7, 2));
        PriceBreakdown visit = Checkout.price(VISIT, List.of(friend));
        System.out.println("разовое и «приведи друга»: " + visit.applied() + " → " + visit.finalMinor());
        PriceBreakdown free = Checkout.price(MONTH, List.of(Discount.percent("100%", 100), Discount.amount("10000", 10_000)));
        System.out.println("после 100 %: " + free.applied() + " → " + free.finalMinor());
        int addsUp = 0;
        List<Long> prices = List.of(1L, 7L, 101L, 250_000L, 333_333L, 999_999L);
        for (long base : prices) {
            PriceBreakdown b = Checkout.price(base, List.of(Discount.percent("p17", 17), Discount.amount("a25", 2_500)));
            long discounts = b.applied().stream().mapToLong(PriceBreakdown.Applied::discountMinor).sum();
            if (discounts + b.finalMinor() == base) {
                addsUp++;
            }
        }
        System.out.println("скидки + итог = цена на неровных ценах: " + addsUp + " из " + prices.size());
        try {
            new PriceBreakdown(100, 60, List.of(new PriceBreakdown.Applied("x", 30)));
            System.out.println("несходящийся разбор: создан");
        } catch (IllegalArgumentException e) {
            System.out.println("несходящийся разбор: " + e.getMessage());
        }
        try {
            year.applied().add(new PriceBreakdown.Applied("x", 1));
            System.out.println("applied().add: добавилось");
        } catch (UnsupportedOperationException e) {
            System.out.println("applied().add: UnsupportedOperationException");
        }
        System.out.println("--- конец");
    }

    // Условие учебной службы из части 2 — как в статье.
    static boolean active(LocalDate today, LocalDate validFrom, LocalDate validTo) {
        return (validFrom == null || !today.isBefore(validFrom))
                && (validTo == null || !today.isAfter(validTo));
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp target/classes "$PROBE"/src/*.java 2>&1)
expect_ok $? "javac пробы"
show "$out"
probe=$(java "${UTF8[@]}" -cp "$PROBE/classes:target/classes" example.crm.MoneyProbe 2>&1)
expect_contains "$probe" "--- конец" "проба дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"
expect_line "$probe" "0.1 + 0.2: 0.30000000000000004" "0.1 + 0.2 — 0.30000000000000004…"
expect_line "$probe" "0.1 + 0.2 == 0.3: false" "…и не равно 0.3"
expect_line "$probe" "1 из 3 в double: 33.333333333333336" "доля статьи 13: 1 из 3 в double — 33.333333333333336…"
expect_line "$probe" "1 из 3 на панели: 33.3" "…а на панели после округления 33,3"
expect_line "$probe" "1.15 * 100: 114.99999999999999" "1.15 * 100 — 114.99999999999999…"
expect_line "$probe" "(long) (1.15 * 100): 114" "…и (long) даёт 114: копейка пропала"
expect_line "$probe" "350_000 * 0.7: 244999.99999999997" "месяц −30 % в double — 244999.99999999997…"
expect_line "$probe" "(long) (350_000 * 0.7): 244999" "…(long) даёт 244 999"
expect_line "$probe" "месяц −30 % в копейках: 245000" "…а в копейках модели ровно 2 450 ₽"
expect_line "$probe" "десять раз по 0.1: 0.9999999999999999" "десять платежей по 10 копеек в double — 0.9999999999999999"
expect_line "$probe" "Integer.MAX_VALUE: 2147483647" "потолок int — 2 147 483 647"
expect_line "$probe" "Long.MAX_VALUE больше 9·10¹⁸: true" "потолок long — больше 9·10¹⁸"
expect_line "$probe" "int: MAX_VALUE + 100 меньше нуля, без исключения: true" "переполнение int исключения не бросает"
expect_line "$probe" "младших разрядов у RUB: 2" "у рубля младших единиц сто…"
expect_line "$probe" "младших разрядов у EUR: 2" "…у евро тоже…"
expect_line "$probe" "младших разрядов у JPY: 0" "…а у иены дробной части нет"
expect_line "$probe" "Rubles.format(3000000): 30 000 ₽" "Rubles: 3 000 000 коп. — «30 000 ₽»"
expect_line "$probe" "Rubles.format(2650050): 26 500,50 ₽" "Rubles: 2 650 050 коп. — «26 500,50 ₽»"
expect_line "$probe" "Rubles.format(5): 0,05 ₽" "Rubles: пять копеек — «0,05 ₽»"
expect_line "$probe" "Rubles.format(-1): сумма меньше нуля: -1" "Rubles: сумма меньше нуля — исключение"
expect_line "$probe" "%,d 30000 в und: 30,000" "Locale.ROOT: 30,000 — запятая"
expect_line "$probe" "%,d 30000 в de-DE: 30.000" "немецкая: 30.000"
expect_line "$probe" "%,d 30000 в de-CH: 30’000" "швейцарская de-CH: 30’000"
expect_line "$probe" "%,d 30000 в ru-RU: 30<U+00A0>000" "русская: неразрывный пробел U+00A0"
expect_line "$probe" "русская равна \"30 000\": false" "…сравнение с \"30 000\" — false"
expect_line "$probe" "русская после замены U+00A0 на пробел равна \"30 000\": true" "…хотя на вид та же строка"
expect_line "$probe" "new BigDecimal(0.1): 0.1000000000000000055511151231257827021181583404541015625" \
    "new BigDecimal(0.1) переносит двоичный хвост"
expect_line "$probe" "new BigDecimal(\"0.1\"): 0.1" "new BigDecimal(\"0.1\") — ровно 0.1"
expect_regex "$probe" '100 / 3 без округления: ArithmeticException: Non-terminating decimal expansion' \
    "деление без округления: ArithmeticException: Non-terminating decimal expansion…"
expect_line "$probe" "100 / 3, 2 знака, HALF_EVEN: 33.33" "divide(…, 2, HALF_EVEN) — 33.33"
expect_line "$probe" "скидка both: скидка both: процент или сумма — ровно одно" "и процент, и сумма — исключение «ровно одно»"
expect_line "$probe" "скидка none: скидка none: процент или сумма — ровно одно" "ни процента, ни суммы — то же"
expect_line "$probe" "скидка zero: скидка zero: процент — от 1 до 100" "процент 0 — «от 1 до 100»…"
expect_line "$probe" "скидка too-much: скидка too-much: процент — от 1 до 100" "…и 101 тоже"
expect_line "$probe" "скидка  : у скидки нет кода" "пустой код — «у скидки нет кода»"
expect_line "$probe" "100 %: Discount[code=free-month, percent=100, amountMinor=null]" "100 % — можно"
expect_line "$probe" "percent(\"year-10\", 10) равна new Discount(\"year-10\", 10, null): true" \
    "фабрика percent — то же, что конструктор с null"
expect_line "$probe" "💡 скидка суммой −50 000 создана: Discount[code=minus, percent=null, amountMinor=-50000]" \
    "💡 скидку −50 000 копеек модель примет"
expect_line "$probe" "💡 её from(годовой): -50000" "💡 …она поднимала бы цену на 500 ₽"
expect_line "$probe" "💡 годовой с ней: 3000000, в разборе: []" "💡 …а расчёт молча её пропустит: цена та же, разбор пуст"
expect_line "$probe" "акция 01.10–07.10, 2026-09-30: false, с isAfter(validFrom): false" "30 сентября акции ещё нет"
expect_line "$probe" "акция 01.10–07.10, 2026-10-01: true, с isAfter(validFrom): false" \
    "1 октября акция действует, а с isAfter(validFrom) первый день выпал бы"
expect_line "$probe" "акция 01.10–07.10, 2026-10-07: true, с isAfter(validFrom): true" "7 октября — действует: границы включительно"
expect_line "$probe" "акция 01.10–07.10, 2026-10-08: false, с isAfter(validFrom): false" "8 октября — уже нет"
expect_line "$probe" "без границ: true" "пустая граница — без ограничения"
expect_line "$probe" "часы 2026-10-07T20:59:00Z по Москве — 2026-10-07: true" "остановленные часы: 23:59 7 октября по Москве — действует…"
expect_line "$probe" "часы 2026-10-07T21:00:00Z по Москве — 2026-10-08: false" "…полночь 8-го — уже нет"
expect_line "$probe" \
    "годовой, за годовой и за друга: [Applied[code=year-10, discountMinor=300000], Applied[code=friend-500, discountMinor=50000]] → 2650000" \
    "«30 000, минус 3 000 за годовой, минус 500 за друга — 26 500»"
expect_line "$probe" "процент → сумма: 2650000" "процент → сумма: 26 500 ₽"
expect_line "$probe" \
    "сумма → процент: [Applied[code=friend-500, discountMinor=50000], Applied[code=year-10, discountMinor=295000]] → 2655000" \
    "сумма → процент: −500, −2 950 от 29 500 — 26 550 ₽; разница 50 ₽"
expect_line "$probe" "ORDER: [a-pct, z-pct, a-flat, b-flat]" "ORDER: сначала проценты, потом суммы, внутри — по коду"
expect_line "$probe" \
    "10 % и 15 % на годовой: [Applied[code=p10, discountMinor=300000], Applied[code=p15, discountMinor=405000]] → 2295000, всего 705000, 23.5 %" \
    "10 % и 15 %: 30 000 → 27 000 → 22 950 ₽, всего −7 050 ₽ — 23,5 %, а не 25"
expect_line "$probe" "271828, 10 % → 15 %: 207948" "2 718,28 ₽: 10 % → 15 % — 2 079,48 ₽…"
expect_line "$probe" "271828, 15 % → 10 %: 207947" "…15 % → 10 % — 2 079,47 ₽"
expect_line "$probe" "101, −50 %: [Applied[code=half, discountMinor=51]] → 50" "101 коп., −50 %: скидка 51, итог 50…"
expect_line "$probe" "101, −50 %, если вниз скидку: скидка 50, итог 51" "…а вниз скидку — скидка 50, итог 51"
expect_line "$probe" "-7 / 2: -3, Math.floorDiv(-7, 2): -4, 7 / 2: 3, Math.floorDiv(7, 2): 3" \
    "-7 / 2 — -3, floorDiv — -4; на положительных одно и то же"
expect_line "$probe" "разовое и «приведи друга»: [Applied[code=friend-500, discountMinor=40000]] → 0" \
    "−500 ₽ на разовое за 400 ₽: дала 400, итог 0"
expect_line "$probe" "после 100 %: [Applied[code=100%, discountMinor=350000]] → 0" "после 100 % следующей нечего снимать — в разбор не попала"
expect_line "$probe" "скидки + итог = цена на неровных ценах: 6 из 6" "1, 7, 101, 250 000, 333 333, 999 999 с −17 % и −25 ₽: сходится"
expect_line "$probe" "несходящийся разбор: разбор не сходится с итогом" "несходящийся разбор не создаётся"
expect_line "$probe" "applied().add: UnsupportedOperationException" "List.copyOf: снаружи разбор не поправят"
show "$(grep -v '^--- конец' <<<"$probe")"

section "Тип в лямбде ORDER написан не зря: без него Checkout не собирается"
v=$(make_variant lambda-type)
perl -pi -e 's/\(Discount discount\) -> !discount\.isPercent\(\)/discount -> !discount.isPercent()/' "$v/$CHECKOUT"
if expect_changed "$v/$CHECKOUT" "$CHECKOUT" "discount -> вместо (Discount discount) ->"; then
    mkdir -p "$v/classes"
    out=$(javac -encoding UTF-8 -proc:none -d "$v/classes" "$v/$CRM"/*.java 2>&1); code=$?
    expect_failed "$code" "javac без типа в лямбде"
    expect_contains "$out" "isPercent()" "…не найден isPercent()…"
    expect_regex "$out" 'type Object|java\.lang\.Object' "…у discount типа Object"
    show "$(head -n 8 <<<"$out")"
fi

section "Что будет, если: «вниз скидку» — Math.floorDiv(price * percent, 100)"
if variant round-discount "$DISCOUNT" \
    's/\? price - Math\.floorDiv\(price \* \(100 - percent\), 100\)/? Math.floorDiv(price * percent, 100)/' \
    "скидка = Math.floorDiv(price * percent, 100)" "$CHECKOUT_CLS"; then
    expect_failed "$CODE" "вниз скидку: CheckoutTest"
    expect_summary "$OUT" 2 0 "вниз скидку"
    expect_red_row "$OUT" "$(row_re 101 50% 50)" "красная строка «101, 50%»…"
    expect_regex "$OUT" 'expected: *<?50L>?' "…expected: 50L…"
    expect_regex "$OUT" 'was: *<?51L>?' "…but was: 51L"
    expect_red "$OUT" roundsTotalDownNotDiscount "красный roundsTotalDownNotDiscount"
    expect_green_row "$OUT" "$(row_re 350000 30% 245000)" "строка −30 % зелёная: делится нацело"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без сортировки в price"
if variant no-sort "$CHECKOUT" 's/discounts\.stream\(\)\.sorted\(ORDER\)\.toList\(\)/discounts/' \
    "price зовёт cascade(baseMinor, discounts)" "$CHECKOUT_CLS"; then
    expect_failed "$CODE" "без сортировки: CheckoutTest"
    expect_summary "$OUT" 1 0 "без сортировки"
    expect_red_row "$OUT" "$(row_re 3000000 '50000;10%' 2650000)" "красная строка «50000;10%»…"
    expect_regex "$OUT" 'expected: *<?2650000L>?' "…expected: 2650000L…"
    expect_regex "$OUT" 'was: *<?2655000L>?' "…but was: 2655000L"
    expect_green_row "$OUT" "$(row_re 3000000 '10%;50000' 2650000)" "«10%;50000» зелёная: порядок и так верный"
    expect_green "$OUT" orderChangesTheTotal "orderChangesTheTotal зелёный: он и так зовёт cascade"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: процент в double — price - (long) (price * (1 - percent / 100.0))"
if variant double-percent "$DISCOUNT" \
    's/Math\.floorDiv\(price \* \(100 - percent\), 100\)/(long) (price * (1 - percent \/ 100.0))/' \
    "price - (long) (price * (1 - percent / 100.0))" "$CHECKOUT_CLS"; then
    expect_failed "$CODE" "процент в double: CheckoutTest"
    expect_summary "$OUT" 1 0 "процент в double"
    expect_red_row "$OUT" "$(row_re 350000 30% 245000)" "красная строка с −30 %…"
    expect_regex "$OUT" 'expected: *<?245000L>?' "…expected: 245000L…"
    expect_regex "$OUT" 'was: *<?244999L>?' "…but was: 244999L — копейка пропала"
    expect_green_row "$OUT" "$(row_re 101 50% 50)" "«101, 50%» зелёная: (long) на положительных — тоже вниз"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без Math.min — скидка больше цены"
if variant no-clamp "$DISCOUNT" 's/return Math\.min\(discount, price\);/return discount;/' \
    "from без Math.min(discount, price)" "$CHECKOUT_CLS"; then
    expect_failed "$CODE" "без Math.min: CheckoutTest"
    expect_summary "$OUT" 3 0 "без Math.min"
    expect_red_row "$OUT" "$(row_re 40000 50000 0)" "красная строка «скидка больше цены»…"
    expect_red_row "$OUT" "$(row_re 350000 '100%;10000' 0)" "…и «после 100 %»…"
    expect_regex "$OUT" 'was: *<?-10000L>?' "…итог -10000"
    expect_red "$OUT" breakdownShowsWhatWasReallyGiven "красный breakdownShowsWhatWasReallyGiven"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без проверки «ровно одно» в конструкторе"
if variant no-exactly-one "$DISCOUNT" 's/\n[ \t]*if \(\(percent == null\) == \(amountMinor == null\)\) \{[^}]*\}//' \
    "Discount без if ((percent == null) == (amountMinor == null))" "$CHECKOUT_CLS" -0pi; then
    expect_not_contains "$(cat "$MUTANT/$DISCOUNT")" "(percent == null) == (amountMinor == null)" "проверки в варианте нет"
    expect_failed "$CODE" "без «ровно одно»: CheckoutTest"
    expect_summary "$OUT" 1 0 "без «ровно одно»"
    expect_red "$OUT" discountIsPercentOrAmountNotBoth "красный discountIsPercentOrAmountNotBoth"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: Locale.of(\"ru\") вместо первого Locale.ROOT в Rubles"
if variant ru-locale "$RUBLES" 's/String\.format\(Locale\.ROOT, "%,d"/String.format(Locale.of("ru"), "%,d"/' \
    "String.format(Locale.of(\"ru\"), \"%,d\", …)" "$RUBLES_CLS"; then
    expect_failed "$CODE" "русская локаль: RublesTest"
    expect_summary "$OUT" 2 0 "русская локаль"
    expect_red_row "$OUT" "$(ruble_re 3000000 '30 000 ₽')" "красная строка «30 000 ₽»…"
    expect_red_row "$OUT" "$(ruble_re 2650050 '26 500,50 ₽')" "…и «26 500,50 ₽»"
    expect_green_row "$OUT" "$(ruble_re 40000 '400 ₽')" "«400 ₽» зелёная: тысяч нет"
    expect_green_row "$OUT" "$(ruble_re 5 '0,05 ₽')" "«0,05 ₽» зелёная"
    expect_contains "$OUT" "\"30${NBSP}000 ₽\"" "в but was — строка с U+00A0…"
    expect_contains "$OUT" '"30 000 ₽"' "…а в expected — с обычным пробелом: на вид одинаковые"
    show "$(red_detail "$OUT")"
fi

section "💡 Без if (given > 0) — все зелёные, а в разборе строка «0 копеек»"
if variant no-given-check "$CHECKOUT" 's/if \(given > 0\) \{/{/' "cascade без if (given > 0)" "$CHECKOUT_CLS"; then
    expect_ok "$CODE" "без if (given > 0): CheckoutTest"
    expect_summary "$OUT" 0 0 "без if (given > 0)"
    expect_regex "$(summary_of "$OUT" 'tests successful')" '^11$' "зелёных по-прежнему 11"
    mkdir -p "$MUTANT/probe"
    out=$(javac -encoding UTF-8 -proc:none -d "$MUTANT/probe" -cp "$MUTANT/classes:target/classes" \
        "$PROBE"/src/*.java 2>&1)
    expect_ok $? "javac пробы на варианте"
    show "$out"
    zero=$(java "${UTF8[@]}" -cp "$MUTANT/probe:$MUTANT/classes:target/classes" example.crm.MoneyProbe 2>&1)
    expect_line "$zero" \
        "после 100 %: [Applied[code=100%, discountMinor=350000], Applied[code=10000, discountMinor=0]] → 0" \
        "после 100 % в разборе — строка «0 копеек»; итог тот же, тест молчит"
fi

section "Часть 2: таблица скидок в Postgres на минуту — SQL из текста статьи"
ARTICLE=${ROOT:-}/articles/14-money-in-code.md
DB=game-day-db
IMAGE=postgres:17-alpine
# SQL-блоки части 2 со sales.discount — по порядку, как их напечатал бы читатель.
article_sql() {
    awk '/^## Часть 2/ { on = 1 } /^## Часть 3/ { on = 0 }
         on && /^```sql$/ { inside = 1; buf = ""; next }
         inside && /^```$/ { inside = 0; if (buf ~ /sales\.discount/) printf "%s", buf; next }
         inside { buf = buf $0 "\n" }' "$ARTICLE"
}
db_down() { docker rm -f "$DB" >/dev/null 2>&1; return 0; }
# psql внутри контейнера; SQL — со стандартного ввода, как если бы его печатали после postgres=#.
psql_in() { docker exec -i "$DB" psql -X -U postgres 2>&1; }
psql_value() { docker exec "$DB" psql -X -U postgres -tA -c "$1" 2>&1; }
db_ok=0
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    sql=$(article_sql)
    expect_contains "$sql" "CREATE TABLE sales.discount" "в части 2 — CREATE TABLE sales.discount"
    expect_contains "$sql" "INSERT INTO sales.discount" "…и INSERT с обеими скидками"
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
    out=$( { echo "CREATE SCHEMA sales;"; echo "$sql"; } | psql_in)
    expect_contains "$out" "CREATE TABLE" "CREATE TABLE из статьи прошёл"
    grep -E '^(ERROR|DETAIL):' "$ARTICLE" >"$PROBE/expected-errors.txt"
    expect_regex "$(grep -c '' "$PROBE/expected-errors.txt")" '^2$' "в статье две строки ответа базы: ERROR и DETAIL"
    while IFS= read -r line; do
        expect_contains "$out" "$line" "ответ базы как в статье: ${line:0:60}…"
    done <"$PROBE/expected-errors.txt"
    show "$(grep -E 'ERROR|DETAIL' <<<"$out")"
    out=$(echo "INSERT INTO sales.discount (code, tariff) VALUES ('none', 'year');" | psql_in)
    expect_contains "$out" 'violates check constraint "discount_percent_or_amount"' "строка без обоих полей — та же ошибка"
    for percent in 0 101; do
        out=$(echo "INSERT INTO sales.discount (code, tariff, percent) VALUES ('p$percent', 'year', $percent);" | psql_in)
        expect_contains "$out" 'violates check constraint "discount_percent_range"' "процент $percent — discount_percent_range"
    done
    out=$( { echo "INSERT INTO sales.discount (code, tariff, percent) VALUES ('free-month', 'month', 100);"
        echo "INSERT INTO sales.discount (code, tariff, percent) VALUES ('year-10', 'year', 10);"
        echo "INSERT INTO sales.discount (code, tariff, amount_minor) VALUES ('friend-500', 'year', 50000);"
        echo "INSERT INTO sales.discount (code, tariff, percent, valid_from, valid_to)"
        echo "VALUES ('autumn-15', 'year', 15, '2026-10-01', '2026-10-07');"; } | psql_in)
    expect_regex "$(grep -c '^INSERT 0 1' <<<"$out")" '^4$' "процент 100 проходит; в таблице четыре скидки"
    out=$(echo "UPDATE sales.discount SET amount_minor = 50000 WHERE code = 'year-10';" | psql_in)
    expect_contains "$out" 'violates check constraint "discount_percent_or_amount"' \
        "UPDATE, дописавший сумму к процентной скидке, — отказ"
    before=$(psql_value "SELECT code FROM sales.discount")
    psql_value "UPDATE sales.discount SET tariff = 'year' WHERE code = 'free-month'" >/dev/null
    after=$(psql_value "SELECT code FROM sales.discount")
    expect_regex "$(head -n 1 <<<"$before")" '^free-month$' "до правки free-month — первая строка SELECT без ORDER BY"
    expect_regex "$(tail -n 1 <<<"$after")" '^free-month$' "после UPDATE та же строка — последняя: порядок без ORDER BY не обещан"
    show "$(printf 'до UPDATE:\n%s\nпосле:\n%s' "$before" "$after")"
    db_down
fi

section "Первоисточники открываются"
for link in https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Math.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/math/BigDecimal.html \
    https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Currency.html \
    https://www.postgresql.org/docs/current/datatype-numeric.html \
    https://www.postgresql.org/docs/current/ddl-constraints.html; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
