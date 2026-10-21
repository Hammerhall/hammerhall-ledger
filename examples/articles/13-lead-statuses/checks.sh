# Статья 13 «Статусы лида: какие ставит человек, а какой — только система» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 12: журнал в example.gameday.journal (18 файлов), сторожа GameDayRulesTest (43 запуска),
# модель статьи 12 в example.crm — FollowUp, TodayList и TodayListTest.
# Код статьи — чистая Java: OrdinalDemo и FunnelNumbers в src/main/java/example/crm, FunnelNumbersTest
# в src/test/java/example/crm. В mvn verify он уже прошёл. Здесь — то, что статья обещает словами:
# 13 запусков теста и 43 у сторожа статьи 11; код без Spring рядом с корнем пакетов; вывод OrdinalDemo — таблица
# части 3 и строка про MEMBER; числа статьи на самой FunnelNumbers (10 % и 25 %, 33 в целых, 6,25 → 6,3, «0 из 0»,
# текст исключения); «что будет, если» из «Порядка проверки» — мутации FunnelNumbers: какие строки таблицы
# краснеют и что приходит вместо ожидаемого; 💡 без if (whole == 0) — всё зелёное; первоисточники открываются.
# Мутации гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в статьях 11 и 12.

CLS=example.crm.FunnelNumbersTest
CRM=src/main/java/example/crm
CRM_TEST=src/test/java/example/crm
FUNNEL=$CRM/FunnelNumbers.java
FUNNEL_TEST=$CRM_TEST/FunnelNumbersTest.java
HERE=$PWD

# Вывод OrdinalDemo — как в статье: таблица части 3 и последняя строка про переименование.
DEMO='записано      номер ORDINAL прочтёт STRING прочтёт
NEW           0     NEW             NEW
IN_PROGRESS   1     IN_PROGRESS     IN_PROGRESS
CONTACTED     2     NO_ANSWER       CONTACTED
BECAME_MEMBER 3     CONTACTED       BECAME_MEMBER
REJECTED      4     BECAME_MEMBER   REJECTED
переименование при STRING: No enum constant example.crm.OrdinalDemo.After.MEMBER'

# Строки таблицы округления из FunnelNumbersTest: клиентов, всего, ожидаемая доля.
ROWS='3 10 30.0
1 3 33.3
2 3 66.7
1 16 6.3
0 0 0.0'

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
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 16; }

# Тест красный / зелёный в дереве. Аргументы: вывод, имя метода, пояснение.
expect_red()   { if red_lines "$1" | grep -qF -- "$2()"; then pass "$3"; else fail "$3: $2 не красный"; fi; }
expect_green() { if grep -qF -- "$2() ✔" <<<"$1"; then pass "$3"; else fail "$3: $2 не зелёный"; fi; }

# Подпись строки таблицы округления в дереве — «"1" из "3" → "33.3"» по name = "{0} из {1} → {2}";
# кавычки вокруг аргументов JUnit ставит сам, здесь они необязательны. Аргументы: клиентов, всего, доля.
row_re() { printf '"?%s"? из "?%s"? → "?%s"?' "$1" "$2" "${3//./\\.}"; }

# Строка таблицы красная / зелёная. Аргументы: вывод, клиентов, всего, доля, пояснение.
expect_red_row() {
    if red_lines "$1" | LC_ALL=C.UTF-8 grep -qE -- "$(row_re "$2" "$3" "$4")"; then
        pass "$5"
    else
        fail "$5: строка «$2 из $3 → $4» не красная"
    fi
}
expect_green_row() {
    if LC_ALL=C.UTF-8 grep -qE -- "$(row_re "$2" "$3" "$4") ✔" <<<"$1"; then
        pass "$5"
    else
        fail "$5: строка «$2 из $3 → $4» не зелёная"
    fi
}

# Правка варианта должна что-то поменять. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    return 0
}

# Собрать код example.crm и FunnelNumbersTest варианта в $1/classes — без target/classes песочницы.
compile_crm() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    if ! javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$CRM"/*.java "$1/$FUNNEL_TEST" >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): example.crm не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# FunnelNumbersTest в ConsoleLauncher на классах из $1.
funnel_test() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" --select-class "$CLS" 2>&1
}

# Вариант: правка файла (perl), сборка, прогон FunnelNumbersTest. Вывод — в $OUT, код выхода — в $CODE,
# папка варианта — в $MUTANT. Аргументы: имя варианта, файл, perl-правка, что правили, флаги perl (необязательно).
OUT=""
CODE=0
MUTANT=""
variant() {
    local name=$1 file=$2 edit=$3 what=$4 flags=${5:--pi} v
    OUT=""
    CODE=0
    v=$(make_variant "$name")
    MUTANT=$v
    perl "$flags" -e "$edit" "$v/$file"
    expect_changed "$v/$file" "$file" "$what" || return 1
    pass "в варианте: $what"
    compile_crm "$v" || return 1
    OUT=$(funnel_test "$v/classes")
    CODE=$?
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CLS" 13
note "13 запусков FunnelNumbersTest: восемь тестов и пять строк таблицы округления"
suite_ok example.crm.TodayListTest 3
suite_ok example.gameday.journal.GameDayRulesTest 43
note "у сторожа статьи 11 по-прежнему 43 запуска: в папку журнала новые классы не попали"
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

section "Код статьи — чистая Java рядом с корнем пакетов, модель статьи 12 на месте"
src=$(cat "$CRM/OrdinalDemo.java" "$FUNNEL")
expect_not_contains "$src" "org.springframework" "в OrdinalDemo и FunnelNumbers нет ни одного импорта Spring"
expect_not_contains "$src" "@Component" "…и ни одной аннотации компонента"
expect_contains "$src" "package example.crm;" "код статьи — в example.crm: рядом с корнем example.gameday, не внутри"
expect_file "$CRM/FollowUp.java"
expect_file "$CRM/TodayList.java"
expect_file "$CRM_TEST/TodayListTest.java"
out=$(funnel_test "$HERE/target/test-classes:$HERE/target/classes"); code=$?
expect_ok "$code" "ConsoleLauncher: FunnelNumbersTest на песочнице"
expect_summary "$out" 0 0 "тест статьи"
expect_regex "$(summary_of "$out" 'tests successful')" '^13$' "зелёных 13: восемь тестов и пять строк таблицы"
while read -r members total share; do
    expect_green_row "$out" "$members" "$total" "$share" "таблица округления: $members из $total → $share"
done <<<"$ROWS"
show "$(grep -E '✔|✘' <<<"$out" | grep -vE 'JUnit|FunnelNumbersTest ')"

section "OrdinalDemo — таблица из части 3 и строка про MEMBER"
demo=$(java "${UTF8[@]}" -cp target/classes example.crm.OrdinalDemo 2>&1); code=$?
expect_ok "$code" "OrdinalDemo"
while IFS= read -r line; do
    expect_line "$demo" "$line" "строка вывода: ${line%% *}"
done <<<"$DEMO"
expect_regex "$(grep -c '' <<<"$demo")" '^7$' "строк ровно семь: заголовок, пять старых статусов, переименование"
expect_line "$demo" "REJECTED      4     BECAME_MEMBER   REJECTED" \
    "🔴 при ORDINAL отказавшиеся стали клиентами, при STRING — как было"
expect_line "$demo" "BECAME_MEMBER 3     CONTACTED       BECAME_MEMBER" "…а настоящие клиенты — «связались»"
show "$demo"

section "Числа статьи — на самой FunnelNumbers"
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/FunnelProbe.java" <<'EOF'
package example.crm;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Map;
import java.util.Set;

// Проба для checks.sh статьи 13: печатает то, что статья обещает словами. В статью не идёт.
public class FunnelProbe {

    public static void main(String[] args) {
        FunnelNumbers hundred = new FunnelNumbers(100, Map.of(
                "NEW", 20L, "REJECTED", 30L, "BECAME_MEMBER", 10L, "IN_PROGRESS", 40L));
        Set<String> decided = Set.of("BECAME_MEMBER", "REJECTED");
        System.out.println("100 лидов, среди всех: " + hundred.shareOfAll("BECAME_MEMBER"));
        System.out.println("100 лидов, среди решённых: " + hundred.shareAmong("BECAME_MEMBER", decided));
        long one = 1;
        long three = 3;
        System.out.println("1 * 100 / 3 в целых: " + one * 100 / three);
        System.out.println("1 из 3 на панели: " + panel(1, 3));
        System.out.println("1 из 16 без округления: " + one * 100.0 / 16);
        System.out.println("1 из 16 на панели: " + panel(1, 16));
        System.out.println("0 из 0: " + panel(0, 0));
        System.out.println("0 из 100: " + panel(0, 100));
        System.out.println("0.0 / 0: " + 0.0 / 0);
        System.out.println("Math.round(NaN): " + Math.round(Double.NaN));
        try {
            new FunnelNumbers(10, Map.of("NEW", 4L));
            System.out.println("4 по статусам при 10 всего: объект создан");
        } catch (IllegalArgumentException e) {
            System.out.println("4 по статусам при 10 всего: " + e.getMessage());
        }
        // Для доли на панели точности double хватает: формула совпадает с точным округлением половины вверх.
        long mismatches = 0;
        for (long total = 1; total <= 2000; total++) {
            for (long members = 0; members <= total; members++) {
                double exact = BigDecimal.valueOf(members * 100)
                        .divide(BigDecimal.valueOf(total), 1, RoundingMode.HALF_UP).doubleValue();
                if (panel(members, total) != exact) {
                    mismatches++;
                }
            }
        }
        System.out.println("до 2000 лидов, расхождений с точным округлением: " + mismatches);
        System.out.println("--- конец");
    }

    static double panel(long members, long total) {
        return new FunnelNumbers(total, Map.of("BECAME_MEMBER", members, "NEW", total - members))
                .shareOfAll("BECAME_MEMBER");
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp target/classes "$PROBE"/src/*.java 2>&1)
expect_ok $? "javac пробы"
show "$out"
probe=$(java "${UTF8[@]}" -cp "$PROBE/classes:target/classes" example.crm.FunnelProbe 2>&1)
expect_contains "$probe" "--- конец" "проба дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"
expect_line "$probe" "100 лидов, среди всех: 10.0" "100 лидов, 10 клиентов — среди всех 10 %"
expect_line "$probe" "100 лидов, среди решённых: 25.0" "…среди тех, чей исход известен, 25 %"
expect_line "$probe" "1 * 100 / 3 в целых: 33" "с целыми числами 1 из 3 — 33"
expect_line "$probe" "1 из 3 на панели: 33.3" "…а с 100.0 — 33,3"
expect_line "$probe" "1 из 16 без округления: 6.25" "1 из 16 — 6,25 %…"
expect_line "$probe" "1 из 16 на панели: 6.3" "…на панели 6,3: половина — вверх"
expect_line "$probe" "0 из 0: 0.0" "«0 из 0» — 0.0…"
expect_line "$probe" "0 из 100: 0.0" "…и «0 из 100» — тоже 0.0"
expect_line "$probe" "4 по статусам при 10 всего: лидов по статусам 4, а всего 10" \
    "по статусам 4, а всего 10 — объекта нет, текст как в статье"
expect_line "$probe" "0.0 / 0: NaN" "💡 0.0 / 0 в double — NaN, а не исключение"
expect_line "$probe" "Math.round(NaN): 0" "💡 Math.round(NaN) — 0"
expect_line "$probe" "до 2000 лидов, расхождений с точным округлением: 0" \
    "для доли на панели точности double хватает: формула = HALF_UP до десятых"
show "$(grep -v '^--- конец' <<<"$probe")"

section "Что будет, если: part * 100 вместо part * 100.0 — деление целое"
if variant int-percent "$FUNNEL" 's/\(part \* 100\.0\)/(part * 100)/' "(part * 100) вместо (part * 100.0)"; then
    expect_failed "$CODE" "part * 100: FunnelNumbersTest"
    expect_summary "$OUT" 3 0 "целое деление"
    expect_red_row "$OUT" 1 3 33.3 "красная «1 из 3»…"
    expect_regex "$OUT" 'was:? *<?33\.0>?' "…пришло 33.0"
    expect_red_row "$OUT" 2 3 66.7 "красная «2 из 3»…"
    expect_regex "$OUT" 'was:? *<?66\.0>?' "…пришло 66.0"
    expect_red_row "$OUT" 1 16 6.3 "красная «1 из 16»…"
    expect_regex "$OUT" 'was:? *<?6\.0>?' "…пришло 6.0"
    expect_green_row "$OUT" 3 10 30.0 "«3 из 10» зелёная — делится нацело"
    expect_green "$OUT" shareAmongDecidedLeavesOutLeadsInProgress "3 из 5 — тоже нацело, 60 %"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: Math.floor вместо Math.round — половина больше не идёт вверх"
if variant floor "$FUNNEL" 's/Math\.round\(raw \* 10\.0\)/Math.floor(raw * 10.0)/' "Math.floor вместо Math.round"; then
    expect_failed "$CODE" "Math.floor: FunnelNumbersTest"
    expect_summary "$OUT" 2 0 "Math.floor"
    expect_red_row "$OUT" 2 3 66.7 "красная «2 из 3»…"
    expect_regex "$OUT" 'was:? *<?66\.6>?' "…пришло 66.6"
    expect_red_row "$OUT" 1 16 6.3 "красная «1 из 16»…"
    expect_regex "$OUT" 'was:? *<?6\.2>?' "…пришло 6.2"
    expect_green_row "$OUT" 1 3 33.3 "«1 из 3» зелёная: 33,33… вниз и так 33,3"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без проверки суммы в конструкторе"
if variant no-sum "$FUNNEL" 's/\n[ \t]*if \(sum != total\) \{[^}]*\}//' "без if (sum != total)" -0pi; then
    expect_not_contains "$(cat "$MUTANT/$FUNNEL")" "sum != total" "проверки в варианте нет"
    expect_failed "$CODE" "без проверки суммы: FunnelNumbersTest"
    expect_summary "$OUT" 1 0 "без проверки суммы"
    expect_red "$OUT" rejectsCountsThatDoNotAddUp "красный rejectsCountsThatDoNotAddUp"
    expect_green "$OUT" rejectsNegativeCount "rejectsNegativeCount зелёный: отрицательное ловит своя проверка"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: без Map.copyOf"
# shellcheck disable=SC2016  # $_ — переменная perl, а не bash
if variant no-copy "$FUNNEL" '$_ = "" if /byStatus = Map\.copyOf\(byStatus\)/' "без byStatus = Map.copyOf(byStatus)"; then
    expect_failed "$CODE" "без Map.copyOf: FunnelNumbersTest"
    expect_summary "$OUT" 1 0 "без Map.copyOf"
    expect_red "$OUT" keepsOwnCopyOfCounts "красный keepsOwnCopyOfCounts"
    expect_regex "$OUT" 'was:? *<?5>?' "…число поменяли снаружи: 5 вместо 1"
    show "$(red_detail "$OUT")"
fi

section "💡 Без if (whole == 0) — все 13 зелёные: 0.0 / 0 — NaN, Math.round(NaN) — 0"
if variant no-zero-check "$FUNNEL" 's/\n[ \t]*if \(whole == 0\) \{[^}]*\}//' "без if (whole == 0)" -0pi; then
    expect_not_contains "$(cat "$MUTANT/$FUNNEL")" "whole == 0" "проверки в варианте нет"
    expect_ok "$CODE" "без проверки на ноль: FunnelNumbersTest"
    expect_summary "$OUT" 0 0 "без проверки на ноль"
    expect_regex "$(summary_of "$OUT" 'tests successful')" '^13$' "зелёных по-прежнему 13"
    expect_green_row "$OUT" 0 0 0.0 "«0 из 0» зелёная и без проверки"
    expect_green "$OUT" nobodyDecidedYetIsZeroNotError "…и nobodyDecidedYetIsZeroNotError"
fi

section "Первоисточники открываются"
for link in https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Enum.html \
    https://docs.hibernate.org/orm/7.0/userguide/html_single/ \
    https://docs.spring.io/spring-boot/api/java/org/springframework/boot/autoconfigure/condition/ConditionalOnProperty.html \
    'https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Math.html#round(double)'; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
