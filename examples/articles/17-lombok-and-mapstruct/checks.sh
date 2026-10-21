# Статья 17 «Lombok и MapStruct: код, который пишут за тебя» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 16: журнал в example.gameday.journal (18 файлов, 2 миграции), сторожа GameDayRulesTest
# (43 запуска), модель статей 12–16 в example.crm и её тесты. Код статьи — чистая Java, без Lombok: LeadCard
# и LeadCardView в src/main/java/example/crm, LeadCardTest в src/test/java/example/crm; pom.xml песочницы
# не меняется. В mvn verify он уже прошёл. Здесь — то, что статья обещает словами: 4 запуска теста и прежние числа
# у тестов 12–16 и сторожа; короткие куски в тексте — те же, что в «Пример целиком»; javap на своей карточке; что
# печатают и как сравниваются LeadCard и LeadCardView; кусок про OffsetDateTime как есть; «что будет, если» —
# мутации своего кода. Обещания о самих Lombok и MapStruct проверяются настоящими обработчиками в отдельной папке,
# мимо песочницы: карточка на Lombok из части 2 даёт тот же .class и проходит тот же тест, без пути к обработчику
# на JDK 23+ сборка падает, без @AllArgsConstructor — тоже, @Data меняет равенство и печать; маппер, ответ и pom
# из части 3 — реализация, как в наброске статьи, @Component от ключа -A, молчание и предупреждение о полях;
# @RequiredArgsConstructor и @Slf4j — по javap. Мутации и тесты гоняются ConsoleLauncher JUnit той же версии,
# что в BOM Boot, — как в 12–16.

CLS=example.crm.LeadCardTest
CRM=src/main/java/example/crm
CRM_TEST=src/test/java/example/crm
CARD=$CRM/LeadCard.java
VIEW=$CRM/LeadCardView.java
CARD_TEST=$CRM_TEST/LeadCardTest.java
HERE=$PWD
ARTICLE=${ROOT:-}/articles/17-lombok-and-mapstruct.md
TESTS='builderKeepsDefaultStatus builderForgetsSourceWithoutDefault viewTakesOnlyListedFields cardsAreNotEqualViewsAre'

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

# Красные строки дерева с первыми строками сообщения — для сводки. Аргумент: вывод ConsoleLauncher.
red_detail() { grep -F -A 3 '✘' <<<"$1" | grep -v '^--$' | head -n 24; }

# Тест красный / зелёный в дереве. Аргументы: вывод, имя метода, пояснение.
expect_red()   { if grep -F '✘' <<<"$1" | grep -qF -- "$2()"; then pass "$3"; else fail "$3: $2 не красный"; fi; }
expect_green() { if grep -qF -- "$2() ✔" <<<"$1"; then pass "$3"; else fail "$3: $2 не зелёный"; fi; }

# Все четыре теста — по списку: красные из $2, остальные зелёные. Аргументы: вывод, красные через пробел.
expect_only_red() {
    local t
    for t in $TESTS; do
        if [[ " $2 " == *" $t "* ]]; then expect_red "$1" "$t" "красный $t"; else expect_green "$1" "$t" "$t зелёный"; fi
    done
}

# Блок кода статьи: первый ```<язык> после строки-заголовка; отступ списка у ограды и строк снимается.
# Аргументы: заголовок (начало строки), язык (пусто — блок без языка).
article_block() {
    awk -v head="$1" -v lang="$2" '
        { line = $0; sub(/^ +/, "", line) }
        !on && index($0, head) == 1 { on = 1; next }
        on && !inside && line == "```" lang { inside = 1; pad = index($0, "`") - 1; next }
        inside && line == "```" { exit }
        inside { print (substr($0, 1, pad) ~ /^ *$/ ? substr($0, pad + 1) : $0) }' "$ARTICLE"
}

# Строки кода без хвостовых комментариев и отступов; пустые и с «…» — мимо. Аргумент: текст.
code_lines() { sed -E 's#[[:space:]]*//.*$##; s/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$1" | grep -v -e '^$' -e '…'; }

# Каждая строка кода из куска статьи есть в файле — без комментариев и отступов. Аргументы: кусок, файл, пояснение.
expect_code_in() {
    local missing
    missing=$(code_lines "$1" | grep -vxF -f <(code_lines "$(cat "$2" 2>/dev/null)"))
    if [ -n "$(code_lines "$1")" ] && [ -z "$missing" ]; then pass "$3"; else fail "$3: строк нет в файле"; show "$missing"; fi
}

# Правка варианта должна что-то поменять. Аргументы: файл варианта, исходный файл, что правили.
expect_changed() {
    if cmp -s "$1" "$2"; then fail "вариант: $3 — правка не легла"; return 1; fi
    return 0
}

# Собрать код example.crm и тест статьи в $1/classes — без target/classes песочницы.
compile_crm() {
    rm -rf "$1/classes" && mkdir -p "$1/classes"
    javac -encoding UTF-8 -proc:none -nowarn -d "$1/classes" -cp "$TEST_DEPS" \
        "$1/$CRM"/*.java "$1/$CARD_TEST" >"$1/javac.log" 2>&1
}

# LeadCardTest в ConsoleLauncher на классах из $1.
crm_test() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" --select-class "$CLS" 2>&1
}

# Вариант: правка файла (perl), сборка, прогон теста. Вывод — в $OUT, код выхода — в $CODE.
# Аргументы: имя варианта, файл, perl-правка, что правили, флаги perl (необязательно).
OUT=""
CODE=0
variant() {
    local name=$1 file=$2 edit=$3 what=$4 flags=${5:--pi} v
    OUT=""
    CODE=0
    v=$(make_variant "$name")
    perl "$flags" -e "$edit" "$v/$file"
    expect_changed "$v/$file" "$file" "$what" || return 1
    pass "в варианте: $what"
    if ! compile_crm "$v"; then
        fail "вариант $name: example.crm не собрался"
        show "$(cat "$v/javac.log")"
        return 1
    fi
    OUT=$(crm_test "$v/classes")
    CODE=$?
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CLS" 4
note "4 запуска LeadCardTest: значение по умолчанию у строителя, источник без него, вид снаружи, равенство"
suite_ok example.crm.PaidSweepTest 13
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
JDK=$(java -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -n 1)
note "JUnit из BOM Boot: ${JUNIT:-не нашёлся}; JDK ${JDK:-?}"
rm -rf target/console
out=$(mvn -B -q -ntp dependency:copy \
    -Dartifact="org.junit.platform:junit-platform-console-standalone:$JUNIT" -DoutputDirectory=target/console 2>&1)
expect_ok $? "ConsoleLauncher JUnit $JUNIT скачан"
CONSOLE=$HERE/target/console/junit-platform-console-standalone-$JUNIT.jar
[ -f "$CONSOLE" ] || show "$(tail -n 20 <<<"$out")"

section "Код статьи — чистая Java без Lombok; короткие куски — те же, что в «Пример целиком»"
src=$(cat "$CARD" "$VIEW")
for word in lombok org.mapstruct org.springframework; do
    expect_not_contains "$src" "$word" "в LeadCard и LeadCardView нет $word"
done
expect_not_contains "$(cat pom.xml)" "lombok" "в pom.xml песочницы Lombok не появился"
expect_not_contains "$(cat pom.xml)" "mapstruct" "…и MapStruct тоже"
expect_regex "$(grep -c '^package example.crm;$' <<<"$src")" '^2$' "обе — в example.crm, рядом с корнем example.gameday"
for file in FollowUp TodayList OrdinalDemo FunnelNumbers Discount PriceBreakdown Checkout Rubles ReminderPoint \
    HeldPlace OpenFollowUp PaidSweep; do
    expect_file "$CRM/$file.java"
done
expect_regex "$(find src/main/java/example/gameday/journal -name '*.java' | grep -c '')" '^18$' \
    "в папке журнала по-прежнему 18 файлов — их и обходит сторож статьи 11"
expect_regex "$(find src/main/resources/db/migration -name '*.sql' | grep -c '')" '^2$' "миграций по-прежнему две"
expect_regex "$(grep -rlE '^[[:space:]]*@(Builder|Getter|Setter|Data|Mapper)|LeadResponseMapper|LeadNote' src | grep -c '')" \
    '^0$' "куски учебной CRM и карточка на Lombok в песочницу не попали"
expect_regex "$(grep -c '' "$CARD")" '^1(4[5-9]|5[0-5])$' "LeadCard целиком — полторы сотни строк ($(grep -c '' "$CARD"))"
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    short=$(article_block "Возьмём шесть полей карточки лида" java)
    expect_contains "$short" "public class LeadCard {" "в части 1 — набросок LeadCard"
    expect_code_in "$short" "$CARD" "каждая строка наброска части 1 — в LeadCard «Пример целиком»"
    short=$(article_block "Значит, строитель должен сам помнить" java)
    expect_contains "$short" "statusSet ? status : LeadCard.defaultStatus()" "в части 1 — флажок statusSet"
    expect_code_in "$short" "$CARD" "status(…) и build() части 1 — те же, что в LeadCard"
    short=$(article_block "на нашей карточке:" java)
    expect_contains "$short" "public static LeadCardView of(LeadCard card)" "в части 4 — LeadCardView с of"
    expect_code_in "$short" "$VIEW" "LeadCardView части 4 — тот же, что в «Пример целиком»"
    short=$(article_block "Последнее — проверить ловушку" java)
    expect_contains "$short" "void builderForgetsSourceWithoutDefault()" "в части 4 — тест на ловушку"
    expect_code_in "$short" "$CARD_TEST" "тест части 4 — тот же, что в LeadCardTest"
fi
out=$(crm_test "$HERE/target/test-classes:$HERE/target/classes"); code=$?
expect_ok "$code" "ConsoleLauncher: LeadCardTest на песочнице"
expect_summary "$out" 0 0 "LeadCardTest"
expect_regex "$(summary_of "$out" 'tests successful')" '^4$' "зелёных 4"
expect_only_red "$out" ""
show "$(grep -E '✔|✘' <<<"$out" | grep -vE 'JUnit|LeadCardTest ')"

section "javap: что лежит в .class своей карточки — как в части 2"
if [ -f "$ARTICLE" ]; then
    listing=$(article_block "**\`javap\`** из JDK печатает" "")
    expect_line "$listing" '$ javap -p -cp target/classes example.crm.LeadCard' "в части 2 — команда javap"
    out=$(javap -p -cp target/classes example.crm.LeadCard 2>&1)
    missing=$(grep -v -e '^\$ ' -e '…' <<<"$listing" | grep -vxF -f <(printf '%s\n' "$out"))
    if [ -z "$missing" ]; then pass "каждая строка вывода javap в статье — в настоящем выводе"; else fail "javap: строк нет"; show "$missing"; fi
    expect_regex "$(grep -c '^  public .*(' <<<"$out")" '^15$' \
        "открытых методов и конструкторов 15: два конструктора, шесть пар геттер-сеттер, builder()"
    show "$out"
fi

section "Что печатают и как сравниваются LeadCard и LeadCardView — на самой модели"
PROBE="$VARIANTS/$(basename "$PWD")-probe"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/CardProbe.java" <<'EOF'
package example.crm;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Проба для checks.sh статьи 17: печатает то, что статья обещает словами, — на самих LeadCard и LeadCardView.
// В статью не идёт.
public class CardProbe {

    public static void main(String[] args) throws Exception {
        LeadCard empty = new LeadCard();
        System.out.println("new LeadCard(): status=" + empty.getStatus() + ", source=" + empty.getSource());
        LeadCard built = LeadCard.builder().firstName("Гость").build();
        System.out.println("строитель без status и source: status=" + built.getStatus() + ", source=" + built.getSource());
        LeadCard byHand = new LeadCard(null, "Гость", null, null, "site", null);
        System.out.println("конструктор на все поля, статус null: status=" + byHand.getStatus());
        LeadCard guest = LeadCard.builder().firstName("Гость").source("site").build();
        System.out.println("вид: " + LeadCardView.of(guest));
        System.out.println("карточка: " + guest);
        LeadCard withPhone = LeadCard.builder().firstName("Гость").phone("+7 900 000-00-00").build();
        System.out.println("телефон в виде: " + LeadCardView.of(withPhone).toString().contains("+7 900"));
        LeadCard one = LeadCard.builder().firstName("Гость").build();
        LeadCard two = LeadCard.builder().firstName("Гость").build();
        System.out.println("карточки равны: " + one.equals(two) + "; виды равны: "
                + LeadCardView.of(one).equals(LeadCardView.of(two)) + ", hashCode видов равны: "
                + (LeadCardView.of(one).hashCode() == LeadCardView.of(two).hashCode()));
        // Момент из теста (args[0]): что значит CREATED по Москве.
        Matcher m = Pattern.compile("CREATED = Instant\\.parse\\(\"([^\"]+)\"\\)").matcher(Files.readString(Path.of(args[0])));
        if (m.find()) {
            Instant created = Instant.parse(m.group(1));
            System.out.println("CREATED: " + created.atZone(ZoneId.of("Europe/Moscow")).getDayOfWeek() + " "
                    + DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm").withZone(ZoneId.of("Europe/Moscow")).format(created));
        }
        System.out.println("--- конец");
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "target/classes" "$PROBE/src/CardProbe.java" 2>&1)
expect_ok $? "javac пробы модели"
show "$out"
probe=$(java "${UTF8[@]}" -cp "$PROBE/classes:target/classes" example.crm.CardProbe "$CARD_TEST" 2>&1)
expect_contains "$probe" "--- конец" "проба модели дошла до конца"
expect_line "$probe" "new LeadCard(): status=NEW, source=call" "пустой конструктор ставит и NEW, и \"call\""
expect_line "$probe" "строитель без status и source: status=NEW, source=null" \
    "строитель: статус NEW по флажку, источник null — про \"call\" он не знает"
expect_line "$probe" "конструктор на все поля, статус null: status=null" "конструктор на все поля кладёт то, что дали"
if [ -f "$ARTICLE" ]; then
    shown=$(article_block "и источником \`\"site\"\` снаружи выглядит так:" "")
    expect_line "$probe" "вид: $shown" "вид снаружи печатается, как в части 4: $shown"
fi
expect_regex "$probe" '^карточка: example\.crm\.LeadCard@[0-9a-f]+$' "LeadCard печатает имя класса, @ и шестнадцатеричное число"
expect_line "$probe" "телефон в виде: false" "телефона в LeadCardView нет — и в печати его нет"
expect_line "$probe" "карточки равны: false; виды равны: true, hashCode видов равны: true" \
    "две карточки с одинаковыми полями не равны, две записи — равны"
expect_line "$probe" "CREATED: MONDAY 05.10.2026 12:15" "CREATED в тесте — понедельник, 5 октября 2026, 12:15 по Москве"
show "$(grep -v '^--- конец' <<<"$probe")"

section "OffsetDateTime → LocalDateTime — кусок части 3 как есть"
if [ -f "$ARTICLE" ]; then
    snippet=$(awk '/^ *```java$/ { inside = 1; buf = ""; next }
        inside && /^ *```$/ { inside = 0; if (buf ~ /OffsetDateTime moscow/) { printf "%s", buf; exit } next }
        inside { buf = buf $0 "\n" }' "$ARTICLE")
    expect_regex "$(grep -c '' <<<"$snippet")" '^4$' "в части 3 — четыре строки про moscow и utc"
    mkdir -p "$PROBE/snippet/classes"
    {
        echo "import java.time.OffsetDateTime;"
        echo "public class SnippetRun {"
        echo "    public static void main(String[] args) {"
        # Выражение без присваивания — напечатать с тем, что обещает комментарий статьи.
        perl -pe 's{^\s*(moscow\S.*?);\s*//\s*(true|false)\b.*$}{System.out.println("$2 " + ($1));}' <<<"$snippet"
        echo "    }"
        echo "}"
    } >"$PROBE/snippet/SnippetRun.java"
    out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/snippet/classes" "$PROBE/snippet/SnippetRun.java" 2>&1)
    expect_ok $? "кусок статьи компилируется как есть"
    show "$out"
    out=$(java "${UTF8[@]}" -cp "$PROBE/snippet/classes" SnippetRun 2>&1)
    expect_regex "$(grep -c '' <<<"$out")" '^2$' "кусок печатает два сравнения"
    expect_line "$out" "true true" "isEqual — true: один и тот же момент"
    expect_line "$out" "false false" "toLocalDateTime().equals — false: 12:15 и 09:15, пояс отброшен"
    show "$out"
fi

section "Что будет, если: убрать флажок из build()"
if variant no-flag "$CARD" 's/statusSet \? status : LeadCard\.defaultStatus\(\)/status/' \
    "build() передаёт status как есть"; then
    expect_failed "$CODE" "без флажка: LeadCardTest"
    expect_summary "$OUT" 2 0 "без флажка"
    expect_only_red "$OUT" "builderKeepsDefaultStatus viewTakesOnlyListedFields"
    expect_regex "$OUT" 'expected: *"NEW"' "…expected: \"NEW\"…"
    expect_regex "$OUT" 'but was: *null' "…but was: null"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: у строителя source = \"call\" в поле — как будто @Builder.Default"
if variant builder-source "$CARD" 's/^        private String source;$/        private String source = "call";/' \
    "в LeadCardBuilder: private String source = \"call\";"; then
    expect_failed "$CODE" "строитель со значением source: LeadCardTest"
    expect_summary "$OUT" 1 0 "строитель со значением source"
    expect_only_red "$OUT" "builderForgetsSourceWithoutDefault"
    expect_contains "$OUT" '"call"' "строитель отдал \"call\" вместо null"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: phone(…) в строителе после копипасты пишет в firstName"
# shellcheck disable=SC2016  # $1 — группа perl, а не bash
if variant phone-copypaste "$CARD" \
    's/(public LeadCardBuilder phone\(String phone\) \{\n\s+this\.)phone = phone;/${1}firstName = phone;/' \
    "LeadCardBuilder.phone(…): this.firstName = phone" -0pi; then
    expect_failed "$CODE" "копипаста в строителе: LeadCardTest"
    expect_summary "$OUT" 1 0 "копипаста в строителе"
    expect_only_red "$OUT" "viewTakesOnlyListedFields"
    expect_contains "$OUT" "name=+7 900 000-00-00" "в имени — телефон"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: equals и hashCode у LeadCard по всем полям, как от @Data"
EQUALS='    @Override
    public boolean equals(Object o) {
        return o instanceof LeadCard other && java.util.Objects.equals(id, other.id)
                && java.util.Objects.equals(firstName, other.firstName) && java.util.Objects.equals(phone, other.phone)
                && java.util.Objects.equals(status, other.status) && java.util.Objects.equals(source, other.source)
                && java.util.Objects.equals(createdAt, other.createdAt);
    }

    @Override
    public int hashCode() {
        return java.util.Objects.hash(id, firstName, phone, status, source, createdAt);
    }
'
export EQUALS
# shellcheck disable=SC2016  # $ENV — переменная perl
if variant equals-all "$CARD" 's{\n    // \@Builder\n}{\n$ENV{EQUALS}\n    // \@Builder\n}' \
    "LeadCard.equals и hashCode по всем шести полям" -0pi; then
    expect_failed "$CODE" "equals по всем полям: LeadCardTest"
    expect_summary "$OUT" 1 0 "equals по всем полям"
    expect_only_red "$OUT" "cardsAreNotEqualViewsAre"
    expect_contains "$OUT" "not to be equal to" "две карточки стали равны"
    show "$(red_detail "$OUT")"
fi

section "Что будет, если: новое поле в LeadCardView, а of не тронут"
v=$(make_variant record-phone)
perl -pi -e 's/String source, Instant createdAt\) \{/String source, Instant createdAt, String phone) {/' "$v/$VIEW"
if expect_changed "$v/$VIEW" "$VIEW" "в запись добавлено поле phone"; then
    pass "в варианте: LeadCardView(…, Instant createdAt, String phone)"
    compile_crm "$v"
    expect_failed $? "LeadCardView с новым полем не собирается"
    expect_contains "$(cat "$v/javac.log")" "constructor LeadCardView in record LeadCardView cannot be applied to given types" \
        "javac: constructor LeadCardView in record LeadCardView cannot be applied to given types"
    show "$(head -n 8 "$v/javac.log")"
fi

section "Настоящий Lombok и MapStruct — в отдельной папке, мимо песочницы"
LOMBOK=$(mvn -B -q -ntp help:evaluate -Dexpression=lombok.version -DforceStdout 2>/dev/null)
expect_regex "$LOMBOK" '^1\.18\.46$' "версию Lombok подставляет родитель Boot 4.1.1: ${LOMBOK:-?}"
MAPSTRUCT=""
BINDING=""
if [ -f "$ARTICLE" ]; then
    pom=$(article_block "версией MapStruct не управляет." xml)
    MAPSTRUCT=$(sed -nE 's#.*<mapstruct.version>([^<]+)</mapstruct.version>.*#\1#p' <<<"$pom")
    BINDING=$(grep -A 1 '<artifactId>lombok-mapstruct-binding</artifactId>' <<<"$pom" | sed -nE 's#.*<version>([^<]+)</version>.*#\1#p')
    expect_regex "$MAPSTRUCT" '^1\.6\.3$' "в pom.xml части 3 MapStruct ${MAPSTRUCT:-?}"
    expect_regex "$BINDING" '^0\.2\.0$' "…и lombok-mapstruct-binding ${BINDING:-?}"
    expect_contains "$pom" "<arg>-Amapstruct.defaultComponentModel=spring</arg>" "…и ключ -Amapstruct.defaultComponentModel=spring"
fi
APT=$HERE/target/apt
rm -rf "$APT"
for artifact in "org.projectlombok:lombok:$LOMBOK" "org.mapstruct:mapstruct:$MAPSTRUCT" \
    "org.mapstruct:mapstruct-processor:$MAPSTRUCT" "org.projectlombok:lombok-mapstruct-binding:$BINDING"; do
    out=$(mvn -B -q -ntp dependency:copy -Dartifact="$artifact" -DoutputDirectory="$APT" 2>&1)
    expect_ok $? "скачан $artifact"
    [ -z "$out" ] || show "$(tail -n 5 <<<"$out")"
done
LOMBOK_JAR=$APT/lombok-$LOMBOK.jar
MS_JAR=$APT/mapstruct-$MAPSTRUCT.jar
MS_PROC=$APT/mapstruct-processor-$MAPSTRUCT.jar
BINDING_JAR=$APT/lombok-mapstruct-binding-$BINDING.jar
entries=$(jar tf "$BINDING_JAR" 2>&1)
expect_contains "$entries" "META-INF/services/org.mapstruct.ap.spi.AstModifyingAnnotationProcessor" \
    "lombok-mapstruct-binding — дополнение к MapStruct…"
expect_not_contains "$entries" "META-INF/services/javax.annotation.processing.Processor" "…а не обработчик аннотаций"

# Папка с карточкой на Lombok из части 2, LeadCardView и LeadCardTest песочницы. Аргумент: имя папки.
lombok_dir() {
    local d
    d="$VARIANTS/$(basename "$HERE")-$1"
    rm -rf "$d" && mkdir -p "$d/src/example/crm" "$d/classes"
    {
        printf 'package example.crm;\n\nimport java.time.Instant;\nimport java.util.UUID;\n\nimport lombok.*;\n\n'
        article_block "Боль, которую он снимает, — вся часть 1." java
    } >"$d/src/example/crm/LeadCard.java"
    cp "$VIEW" "$d/src/example/crm/LeadCardView.java"
    cp "$CARD_TEST" "$d/src/example/crm/LeadCardTest.java"
    echo "$d"
}

section "Lombok: карточка из части 2 — тот же .class и тот же тест"
L=$(lombok_dir lombok)
expect_regex "$(article_block "Боль, которую он снимает, — вся часть 1." java | grep -c '')" '^15$' \
    "карточка на Lombok в части 2 — пятнадцать строк"
out=$(javac -encoding UTF-8 -d "$L/classes" -cp "$LOMBOK_JAR:$TEST_DEPS" -processorpath "$LOMBOK_JAR" \
    "$L"/src/example/crm/*.java 2>&1)
expect_ok $? "javac с путём к Lombok: карточка из части 2 собралась вместе с LeadCardView и LeadCardTest"
expect_regex "$(grep -c '@Builder will ignore the initializing expression entirely' <<<"$out")" '^1$' \
    "одно предупреждение «@Builder will ignore the initializing expression entirely»…"
expect_contains "$out" 'private String source = "call";' "…и оно про source, где нет @Builder.Default"
show "$out"
hand=$(javap -public -cp target/classes example.crm.LeadCard | sort)
lomb=$(javap -public -cp "$L/classes" example.crm.LeadCard | sort)
if [ -n "$lomb" ] && [ "$hand" = "$lomb" ]; then
    pass "javap -public: у LeadCard на Lombok те же конструкторы, геттеры, сеттеры и builder(), что руками"
else
    fail "javap -public LeadCard: Lombok и руками разошлись"
    show "$(diff <(printf '%s\n' "$hand") <(printf '%s\n' "$lomb"))"
fi
BUILDER="example.crm.LeadCard\$LeadCardBuilder"
hand=$(javap -public -cp target/classes "$BUILDER" | sort)
lomb=$(javap -public -cp "$L/classes" "$BUILDER" | sort)
extra=$(comm -13 <(printf '%s\n' "$hand") <(printf '%s\n' "$lomb"))
gone=$(comm -23 <(printf '%s\n' "$hand") <(printf '%s\n' "$lomb"))
if [ -n "$lomb" ] && [ -z "$gone" ] && [ "$extra" = "  public java.lang.String toString();" ]; then
    pass "строитель: те же методы, у Lombok сверх того только toString()"
else
    fail "строитель: Lombok и руками разошлись"
    show "$(printf 'только руками:\n%s\nтолько Lombok:\n%s' "$gone" "$extra")"
fi
priv=$(javap -p -cp "$L/classes" example.crm.LeadCard "$BUILDER" 2>&1)
# shellcheck disable=SC2016  # $ — часть имён, которые пишет Lombok
expect_contains "$priv" 'private static java.lang.String $default$status();' "у Lombok значение по умолчанию — \$default\$status()…"
# shellcheck disable=SC2016
expect_contains "$priv" 'private boolean status$set;' "…а флажок в строителе — status\$set"
out=$(crm_test "$L/classes"); code=$?
expect_ok "$code" "ConsoleLauncher: LeadCardTest на карточке из Lombok"
expect_summary "$out" 0 0 "LeadCardTest на Lombok"
expect_only_red "$out" ""

section "Lombok: без пути к обработчику"
L2=$(lombok_dir no-processor-path)
out=$(javac -encoding UTF-8 -d "$L2/classes" -cp "$LOMBOK_JAR:$TEST_DEPS" "$L2"/src/example/crm/*.java 2>&1); code=$?
if [ "${JDK:-0}" -ge 23 ]; then
    expect_failed "$code" "JDK $JDK, Lombok только среди библиотек: сборка падает"
    expect_contains "$out" "cannot find symbol" "…cannot find symbol"
    expect_regex "$(grep -cE 'LeadCard(View|Test)\.java:[0-9]+: error' <<<"$out")" '^[1-9][0-9]*$' \
        "ошибки — у тех, кто зовёт builder() и геттеры…"
    expect_regex "$(grep -cE '/LeadCard\.java:[0-9]+: error' <<<"$out")" '^0$' "…а сама LeadCard собралась: аннотации — просто надписи"
else
    note "JDK $JDK: обработчики ещё ищутся среди библиотек, код выхода $code — проверка про JDK 23+ здесь не к месту"
fi
show "$(head -n 12 <<<"$out")"

section "Lombok: без @AllArgsConstructor строителю не на чем собрать карточку"
L3=$(lombok_dir no-all-args)
perl -ni -e 'print unless /^\@AllArgsConstructor$/' "$L3/src/example/crm/LeadCard.java"
expect_not_contains "$(cat "$L3/src/example/crm/LeadCard.java")" "@AllArgsConstructor" "в варианте нет @AllArgsConstructor"
out=$(javac -encoding UTF-8 -d "$L3/classes" -cp "$LOMBOK_JAR:$TEST_DEPS" -processorpath "$LOMBOK_JAR" \
    "$L3"/src/example/crm/*.java 2>&1)
expect_failed $? "@Builder и @NoArgsConstructor без @AllArgsConstructor: сборка падает"
expect_regex "$out" 'LeadCard.*(cannot be applied to given types|no suitable constructor)' \
    "…build() зовёт конструктор на все поля, которого нет"
show "$(head -n 12 <<<"$out")"

section "Lombok: @Data на карточке — равенство и печать по всем полям"
L4=$(lombok_dir data)
perl -pi -e 's/^\@Builder$/\@Data\n\@Builder/' "$L4/src/example/crm/LeadCard.java"
expect_contains "$(cat "$L4/src/example/crm/LeadCard.java")" "@Data" "в варианте над карточкой @Data"
out=$(javac -encoding UTF-8 -d "$L4/classes" -cp "$LOMBOK_JAR:$TEST_DEPS" -processorpath "$LOMBOK_JAR" \
    "$L4"/src/example/crm/*.java 2>&1)
expect_ok $? "javac: карточка с @Data собралась"
OUT=$(crm_test "$L4/classes")
expect_summary "$OUT" 1 0 "@Data"
expect_only_red "$OUT" "cardsAreNotEqualViewsAre"
expect_contains "$OUT" "LeadCard(id=7f3c2a10-0000-4000-8000-000000000017, firstName=Гость, phone=null" \
    "toString() от Lombok — круглые скобки и каждое поле, телефон тоже"
show "$(red_detail "$OUT")"

section "MapStruct: маппер, ответ и pom.xml части 3 — с Lombok и посредником"
M="$VARIANTS/$(basename "$HERE")-mapstruct"
rm -rf "$M" && mkdir -p "$M/src/example/crm" "$M/classes" "$M/gen"
J="$M/src/example/crm"
head_of() { printf 'package example.crm;\n\nimport java.time.Clock;\nimport java.time.Instant;\nimport java.util.UUID;\n\n'; }
{
    head_of
    printf 'import jakarta.persistence.*;\nimport lombok.*;\n\n'
    article_block "Вот как это выглядит на сущности." java \
        | perl -pe 's{^    // … источник.*$}{    private String source;\n    private String channel;\n    private String interest;\n    private String manager;\n    private Instant createdAt;}'
} >"$J/Lead.java"
printf 'package example.crm;\n\npublic enum LeadStatus { NEW, IN_PROGRESS, CONTACTED, BECAME_MEMBER, REJECTED }\n' >"$J/LeadStatus.java"
{ head_of; printf 'import lombok.*;\n\n'; article_block "И ответ, в который он переводит" java; } >"$J/LeadResponse.java"
{ head_of; printf 'import org.mapstruct.*;\n\n'; article_block "не трогает. Маппер лида учебной CRM" java; } >"$J/LeadResponseMapper.java"
{ head_of; printf 'import org.mapstruct.*;\n\n'; article_block "* разные имена — аннотацией" java; } >"$J/LeadNoteMapper.java"
{
    head_of
    printf 'import org.springframework.stereotype.Service;\nimport lombok.*;\nimport lombok.extern.slf4j.Slf4j;\n\n'
    article_block "Служба лидов учебной CRM, начало класса:" java | perl -pe 's/^\@Service$/\@Slf4j\n\@Service/'
    printf '    private int handled;                     // не final — в конструктор не попадёт\n}\n'
} >"$J/LeadService.java"
cat >"$J/LeadNote.java" <<'EOF'
package example.crm;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.*;
import lombok.*;

// Заметка менеджера — как кусок части 2, целиком. В статью не идёт.
@Entity
@Table(name = "lead_note")
@Getter
@Setter
@NoArgsConstructor
public class LeadNote {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "lead_id", nullable = false)
    private Lead lead;

    private String body;
    private Instant createdAt;
}
EOF
# Ответ заметки — запись из части 3; остальное — для «что будет, если» и для LeadService. В статью не идёт.
small() { printf 'package example.crm;\n\n%s\n' "$2" >"$J/$1.java"; }
small LeadNoteResponse 'import java.time.Instant;
import java.util.UUID;

public record LeadNoteResponse(UUID id, UUID leadId, String text, Instant createdAt) {
}'
small LeadRepository 'public interface LeadRepository {
}'
small LeadNotifier 'public interface LeadNotifier {
}'
small LeadShort '/** В ответе поле зовётся name, а в сущности — firstName: так выглядит переименование. */
@lombok.Data
public class LeadShort {
    private String name;
    private String status;
}'
small LeadShortMapper '@org.mapstruct.Mapper
public interface LeadShortMapper {
    LeadShort toShort(Lead lead);
}'
ms_compile() {
    javac -encoding UTF-8 -d "$1/classes" -s "$1/gen" -cp "$LOMBOK_JAR:$MS_JAR:$TEST_DEPS" \
        -processorpath "$LOMBOK_JAR:$MS_PROC:$BINDING_JAR" "${@:2}" "$J"/*.java 2>&1
}
out=$(ms_compile "$M" -Amapstruct.defaultComponentModel=spring); code=$?
expect_ok "$code" "javac: Lombok, MapStruct и посредник в одной сборке — куски части 2 и 3 собрались"
show "$out"
expect_regex "$(grep -c 'Unmapped target' <<<"$out")" '^1$' "предупреждение о поле ответа — одно…"
expect_contains "$out" 'Unmapped target property: "name".' "…Unmapped target property: \"name\". — поле ответа без пары в сущности"
expect_regex "$(grep -i 'warning:' <<<"$out" | grep -ciE 'unmapped source|channel|interest|manager')" '^0$' \
    "поля сущности, которых нет в ответе, MapStruct пропустил молча"
IMPL=$M/gen/example/crm/LeadResponseMapperImpl.java
expect_file "$IMPL"
expect_contains "$(cat "$IMPL" 2>/dev/null)" "@Component" "с ключом -A на реализации @Component — она бин"
if [ -f "$ARTICLE" ]; then
    sketch=$(article_block "пишет реализацию маппера лида, сокращено:" java)
    expect_contains "$sketch" "LeadResponse.LeadResponseBuilder leadResponse = LeadResponse.builder();" "в части 3 — набросок реализации"
    expect_code_in "$sketch" "$IMPL" "каждая строка наброска — в настоящей реализации от MapStruct"
fi
expect_regex "$(grep -cE '^ +leadResponse\.[A-Za-z]+\( lead\.get[A-Za-z]+\(\) \);$' "$IMPL" 2>/dev/null)" '^6$' \
    "одинаковых имён шесть: id, firstName, «ещё три» — phone, messenger, email — и createdAt"
expect_not_contains "$(cat "$M/gen/example/crm/LeadShortMapperImpl.java" 2>/dev/null)" "setName(" \
    "переименование: поле name ответа никто не заполнил — в нём null"
expect_contains "$(cat "$M/gen/example/crm/LeadNoteMapperImpl.java" 2>/dev/null)" "note.getBody()" \
    "@Mapping: text берётся из body…"
expect_contains "$(cat "$M/gen/example/crm/LeadNoteMapperImpl.java" 2>/dev/null)" "new LeadNoteResponse(" \
    "…а запись ответа MapStruct собирает её конструктором"
show "$(sed -n '/^@Component/,$p' "$IMPL" 2>/dev/null)"
svc=$(javap -p -cp "$M/classes" example.crm.LeadService 2>&1)
expect_contains "$svc" \
    "public example.crm.LeadService(example.crm.LeadRepository, example.crm.LeadResponseMapper, example.crm.LeadNotifier, java.time.Clock);" \
    "@RequiredArgsConstructor: четыре final-поля в порядке объявления, handled без final — мимо"
expect_contains "$svc" "private static final org.slf4j.Logger log;" "@Slf4j: поле log"
show "$svc"
M2="$VARIANTS/$(basename "$HERE")-mapstruct-default"
rm -rf "$M2" && mkdir -p "$M2/classes" "$M2/gen"
out=$(ms_compile "$M2"); code=$?
expect_ok "$code" "без ключа -A тоже собирается"
expect_file "$M2/gen/example/crm/LeadResponseMapperImpl.java"
expect_not_contains "$(cat "$M2/gen/example/crm/LeadResponseMapperImpl.java" 2>/dev/null)" "@Component" \
    "…но @Component на реализации нет: маппер достают через Mappers.getMapper"

section "Первоисточники открываются"
for link in https://projectlombok.org/features/Builder \
    https://projectlombok.org/setup/maven \
    https://mapstruct.org/documentation/stable/reference/html/ \
    https://docs.hibernate.org/orm/7.4/introduction/html_single/ \
    https://openjdk.org/jeps/395; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
