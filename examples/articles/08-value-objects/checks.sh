# Статья 8 «Объекты-значения» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
# Закрывает лист сборки статьи: @ValueSource без обрезки, AssertJ из BOM, StopWord в JSON,
# {} логгера, покрытие. Тесты статьи уже прогнал mvn verify — здесь то, что статья
# показывает комментариями «вот что выйдет» и обещает словами.

MAIN=src/main/java/example/gameday
TEST=src/test/java/example/gameday
DEMO=target/demo

# Демо-программы: печатают то, что статья показывает в коротких примерах. В статью не идут.
demo_compile() {
    rm -rf "$DEMO/classes" && mkdir -p "$DEMO/classes"
    javac -J-Duser.language=en -encoding UTF-8 -d "$DEMO/classes" -cp "$(classpath)" "$DEMO"/src/*.java 2>&1
}
run_demo() { local cls=$1; shift; java "${UTF8[@]}" "$@" -cp "$(classpath):$DEMO/classes" "$cls" 2>&1; }

# Что демо напечатало после метки: строка, которая начинается с «метка → », без метки.
result_of() {
    local line
    line=$(P="$2 → " awk 'index($0, ENVIRON["P"]) == 1 { print; exit }' <<<"$1")
    echo "${line#*" → "}"
}

# Прогнать тесты варианта; печатает вывод Maven, код выхода — как у Maven.
variant_test() { (cd "$1" && shift && mvn -B -ntp test "$@" 2>&1); }

# Тесты с JaCoCo из командной строки: в pom.xml песочницы его нет.
JACOCO=org.jacoco:jacoco-maven-plugin:0.8.15
jacoco_test() { mvn -B -ntp "$JACOCO:prepare-agent" test "$JACOCO:report" "$@" 2>&1; }

# Покрытие одной строки по отчёту JaCoCo: «mi ci mb cb» — инструкции и ветки, пропущено/пройдено.
line_coverage() {
    python3 - "$@" <<'PY'
import sys, xml.etree.ElementTree as ET
report, source, nr = sys.argv[1:4]
package, name = source.rsplit("/", 1)
for pkg in ET.parse(report).getroot().iter("package"):
    if pkg.get("name") != package:
        continue
    for sf in pkg.iter("sourcefile"):
        if sf.get("name") == name:
            for line in sf.iter("line"):
                if line.get("nr") == nr:
                    print(line.get("mi"), line.get("ci"), line.get("mb"), line.get("cb"))
PY
}

# Сводка JaCoCo по классам статьи — для сверки, в статью не идёт.
coverage_summary() {
    python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
wanted = ["example/gameday/journal/DutyName", "example/gameday/StopWord",
          "example/gameday/journal/AttackOutcome"]
found = {}
for cls in ET.parse(sys.argv[1]).getroot().iter("class"):
    if cls.get("name") in wanted:
        c = {x.get("type"): (int(x.get("covered")), int(x.get("missed"))) for x in cls.findall("counter")}
        line, branch = c.get("LINE", (0, 0)), c.get("BRANCH", (0, 0))
        found[cls.get("name")] = (f"{cls.get('name').rsplit('/', 1)[1]}: строк {line[0]} из {sum(line)}, "
                                  f"веток {branch[0]} из {sum(branch)}")
for name in wanted:
    print(found.get(name, name + ": нет в отчёте"))
PY
}

mkdir -p "$DEMO/src"

cat >"$DEMO/src/Demo.java" <<'EOF'
import example.gameday.GameDayProperties;
import example.gameday.StopWord;
import example.gameday.journal.AttackOutcome;
import example.gameday.journal.DutyName;

import java.time.Duration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public class Demo {

    record Game(String title, StopWord stopWord) {}

    static void attempt(String label, Runnable action) {
        try {
            action.run();
            System.out.println(label + " → создан");
        } catch (RuntimeException e) {
            System.out.println(label + " → " + e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }

    public static void main(String[] args) {
        var gameDay = new GameDayProperties(Duration.ofHours(3), "red-fox", 2);
        System.out.println("toString → " + DutyName.of("duty-1").toString());
        System.out.println("настройки: " + gameDay);
        System.out.println("стоп-слово: " + StopWord.of("red-fox"));
        System.out.println("Game → " + new Game("игровой день", StopWord.of("red-fox")));

        System.out.println("of(\" Duty-1 \").equals(of(\"duty-1\")) → "
                + DutyName.of(" Duty-1 ").equals(DutyName.of("duty-1")));
        System.out.println("\" Duty-1 \".equals(\"duty-1\") → " + " Duty-1 ".equals("duty-1"));

        Set<DutyName> onDuty = new HashSet<>();
        onDuty.add(DutyName.of("duty-1"));
        boolean second = onDuty.add(DutyName.of(" DUTY-1 "));
        Set<String> raw = new HashSet<>(Set.of("duty-1", " DUTY-1 "));
        System.out.println("второй add → " + second + ", size " + onDuty.size() + ", строк " + raw.size());
        Map<DutyName, Integer> openByDuty = new HashMap<>();
        openByDuty.put(DutyName.of("duty-1"), 3);
        System.out.println("get(of(\"DUTY-1\")) → " + openByDuty.get(DutyName.of("DUTY-1")));
        System.out.println("StopWord.of(\" red-fox \").equals(StopWord.of(\"red-fox\")) → "
                + StopWord.of(" red-fox ").equals(StopWord.of("red-fox")));

        String wide = "\u2003duty-1";
        String nbsp = "\u00A0duty-1";
        String control = "\u0001duty-1\u0000";
        System.out.println("\\u2003duty-1 → trim: длина " + wide.trim().length()
                + ", strip: " + wide.strip());
        System.out.println("\\u00A0duty-1 → trim: длина " + nbsp.trim().length()
                + ", strip: длина " + nbsp.strip().length());
        System.out.println("\\u0001duty-1\\u0000 → trim: длина " + control.trim().length()
                + ", strip: длина " + control.strip().length());
        System.out.println("isWhitespace(U+00A0) → " + Character.isWhitespace(0xA0));
        System.out.println("KIRA tr → " + "KIRA".toLowerCase(Locale.forLanguageTag("tr")));
        System.out.println("KIRA ROOT → " + "KIRA".toLowerCase(Locale.ROOT));

        attempt("of(null)", () -> DutyName.of(null));
        attempt("of(\"   \")", () -> DutyName.of("   "));
        attempt("of(50 знаков)", () -> DutyName.of("d".repeat(50)));
        attempt("of(51 знак)", () -> DutyName.of("d".repeat(51)));
        attempt("new DutyName(\" Duty-1 \")", () -> new DutyName(" Duty-1 "));
        attempt("of(\"\\u0000duty-1\")", () -> DutyName.of("\u0000duty-1"));
        attempt("of(\"\\u00A0duty-1\")", () -> DutyName.of("\u00A0duty-1"));
        attempt("of(\"duty-\")", () -> DutyName.of("duty-"));
        attempt("of(\"d--1\")", () -> DutyName.of("d--1"));
        attempt("of(\"Иван Петров\")", () -> DutyName.of("Иван Петров"));
        attempt("StopWord.of(\"${GAME_DAY_STOP_WORD}\")", () -> StopWord.of("${GAME_DAY_STOP_WORD}"));
        attempt("new StopWord(\" red-fox \")", () -> new StopWord(" red-fox "));
        attempt("StopWord.of(\"   \")", () -> StopWord.of("   "));
        attempt("StopWord.of(null)", () -> StopWord.of(null));

        for (int exitCode : new int[] {0, 1, 2, 127, 130, 137, -1}) {
            AttackOutcome outcome = AttackOutcome.fromExitCode(exitCode);
            System.out.println("fromExitCode(" + exitCode + ") → " + outcome + " (" + outcome.code() + ")");
        }
        attempt("values()[127]", () -> System.out.println(AttackOutcome.values()[127]));
    }
}
EOF

cat >"$DEMO/src/DemoLocale.java" <<'EOF'
import example.gameday.journal.DutyName;

import java.util.Locale;

public class DemoLocale {

    public static void main(String[] args) {
        String naive = "KIRA".toLowerCase();
        System.out.println("локаль → " + Locale.getDefault());
        System.out.println("\"KIRA\".toLowerCase() → " + naive);
        System.out.println("форма [a-z][a-z0-9-]* → " + naive.matches("[a-z][a-z0-9-]*"));
        System.out.println("DutyName.of(\"KIRA\") → " + DutyName.of("KIRA").value());
    }
}
EOF

cat >"$DEMO/src/DemoLog.java" <<'EOF'
import example.gameday.GameDayProperties;
import example.gameday.StopWord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;

public class DemoLog {

    private static final Logger logger = LoggerFactory.getLogger(DemoLog.class);

    public static void main(String[] args) {
        var gameDay = new GameDayProperties(Duration.ofHours(3), "red-fox", 2);
        logger.info("настройки: {}", gameDay);
        logger.info("стоп-слово: {}", StopWord.of("red-fox"));
    }
}
EOF

cat >"$DEMO/src/DemoJson.java" <<'EOF'
import example.gameday.StopWord;
import tools.jackson.databind.json.JsonMapper;

public class DemoJson {

    public record GameAnswer(String title, StopWord stopWord) {}

    public static void main(String[] args) {
        JsonMapper mapper = JsonMapper.builder().build();
        System.out.println(mapper.writeValueAsString(new GameAnswer("игровой день", StopWord.of("red-fox"))));
    }
}
EOF

section "Демо-программы компилируются против кода статьи"
out=$(demo_compile); code=$?
expect_ok "$code" "javac демо"
[ "$code" -eq 0 ] || show "$out"

section "toString записи: склейка через + печатает поля, StopWord — маску"
out=$(run_demo Demo); code=$?
expect_ok "$code" "Demo"
expect_contains "$out" "toString → DutyName[value=duty-1]" "DutyName.of(\"duty-1\").toString()"
expect_contains "$out" "настройки: GameDayProperties[length=PT3H, stopWord=red-fox, attackers=2]" \
    "\"настройки: \" + gameDay выдаёт стоп-слово"
expect_contains "$out" "стоп-слово: StopWord[скрыто]" "\"стоп-слово: \" + word"
expect_contains "$out" "Game → Game[title=игровой день, stopWord=StopWord[скрыто]]" \
    "запись, которая держит StopWord, печатает маску"
show "$(grep -E '^(toString →|настройки:|стоп-слово:|Game →)' <<<"$out")"

section "Равенство и коллекции"
expect_contains "$out" "of(\" Duty-1 \").equals(of(\"duty-1\")) → true" "DutyName равны после приведения"
expect_contains "$out" "\" Duty-1 \".equals(\"duty-1\") → false" "строки — разные"
expect_contains "$out" "второй add → false, size 1, строк 2" "HashSet: один DutyName, две строки"
expect_contains "$out" "get(of(\"DUTY-1\")) → 3" "ключ Map найден"
expect_contains "$out" "StopWord.of(\" red-fox \").equals(StopWord.of(\"red-fox\")) → true" \
    "сверка со словом без value()"
show "$(grep -E 'equals|add|get\(' <<<"$out")"

section "strip() и trim(): кто какие знаки снимает"
expect_contains "$out" "\\u2003duty-1 → trim: длина 7, strip: duty-1" "широкий пробел: trim оставляет, strip снимает"
expect_contains "$out" "\\u00A0duty-1 → trim: длина 7, strip: длина 7" "неразрывный пробел не снимает ни тот, ни другой"
expect_contains "$out" "\\u0001duty-1\\u0000 → trim: длина 6, strip: длина 8" \
    "служебные знаки: trim срезает, strip оставляет"
expect_contains "$out" "isWhitespace(U+00A0) → false" "Character.isWhitespace(U+00A0) — false"
show "$(grep -E 'trim|isWhitespace' <<<"$out")"

section "Локаль: KIRA в турецкой и в Locale.ROOT"
expect_contains "$out" "KIRA tr → kıra" "\"KIRA\".toLowerCase(tr) — i без точки"
expect_contains "$out" "KIRA ROOT → kira" "\"KIRA\".toLowerCase(Locale.ROOT)"
tr=$(run_demo DemoLocale -Duser.language=tr -Duser.country=TR); code=$?
expect_ok "$code" "DemoLocale с турецкой локалью по умолчанию"
expect_contains "$tr" "\"KIRA\".toLowerCase() → kıra" "toLowerCase() без локали берёт турецкую"
expect_contains "$tr" "форма [a-z][a-z0-9-]* → false" "проверка формы отвергла бы kıra"
expect_contains "$tr" "DutyName.of(\"KIRA\") → kira" "с Locale.ROOT — kira на любой машине"
show "$(grep -E 'KIRA' <<<"$out")"$'\n'"$tr"

section "Тексты ошибок DutyName: «не указано», длина, форма, обход of"
expect_contains "$(result_of "$out" 'of(null)')" "IllegalArgumentException: имя дежурного не указано" "of(null)"
expect_contains "$(result_of "$out" 'of("   ")')" "имя дежурного не указано" "of(\"   \") — «не указано», а не «неверная форма»"
expect_contains "$(result_of "$out" 'of(50 знаков)')" "создан" "50 знаков — годно"
expect_contains "$(result_of "$out" 'of(51 знак)')" "имя дежурного длиннее 50 знаков" "51 знак — ошибка"
expect_contains "$(result_of "$out" 'new DutyName(" Duty-1 ")')" "создавай через DutyName.of" \
    "мимо of не создаётся, текст подсказывает"
expect_contains "$(result_of "$out" 'of("\u0000duty-1")')" "IllegalArgumentException" "служебный знак отвергает форма"
expect_contains "$(result_of "$out" 'of("\u00A0duty-1")')" "IllegalArgumentException" "неразрывный пробел отвергает форма"
expect_contains "$(result_of "$out" 'of("duty-")')" "создан" "край: duty- форма пропускает"
expect_contains "$(result_of "$out" 'of("d--1")')" "создан" "край: d--1 форма пропускает"
expect_not_contains "$(result_of "$out" 'of("Иван Петров")')" "Иван" "имя в текст ошибки не попадает"
expect_not_contains "$(result_of "$out" 'of("Иван Петров")')" "иван" "и приведённое имя — тоже"
show "$(grep -E '^(of\(|new DutyName)' <<<"$out" | grep -v -F 'equals')"

section "Тексты ошибок StopWord — без значения"
# shellcheck disable=SC2016  # ${GAME_DAY_STOP_WORD} — буквально, как в статье
expect_contains "$(result_of "$out" 'StopWord.of("${GAME_DAY_STOP_WORD}")')" \
    "стоп-слово не задано: переменная окружения не подставилась" "ловушка из статьи 2 — в самом типе"
expect_contains "$(result_of "$out" 'new StopWord(" red-fox ")')" \
    "стоп-слово с пробелами по краям — создавай через StopWord.of" "мимо of с пробелами не пройти"
expect_not_contains "$(result_of "$out" 'new StopWord(" red-fox ")')" "red-fox" "в тексте ошибки нет red-fox"
expect_contains "$(result_of "$out" 'StopWord.of("   ")')" "стоп-слово не задано" "пустое стоп-слово"
expect_contains "$(result_of "$out" 'StopWord.of(null)')" "стоп-слово не задано" "null"
show "$(grep -E 'StopWord\.of\(|new StopWord' <<<"$out" | grep -F 'Exception')"

section "AttackOutcome: чужой код выхода — в свой исход"
expect_contains "$out" "fromExitCode(0) → HIT (hit)" "0 — HIT"
expect_contains "$out" "fromExitCode(1) → REPELLED (repelled)" "1 — REPELLED"
for c in 2 127 130 137 -1; do
    expect_contains "$out" "fromExitCode($c) → SCRIPT_FAILED (script-failed)" "$c — SCRIPT_FAILED"
done
expect_contains "$(result_of "$out" 'values()[127]')" "ArrayIndexOutOfBoundsException" \
    "values()[127] — ArrayIndexOutOfBoundsException"
show "$(grep -E 'fromExitCode|values\(\)' <<<"$out")"

section "switch по int без default не компилируется"
v=$(make_variant no-default)
sed -i '/default -> SCRIPT_FAILED;/d' "$v/$MAIN/journal/AttackOutcome.java"
expect_not_contains "$(cat "$v/$MAIN/journal/AttackOutcome.java")" "default ->" "default убран из варианта"
mkdir -p "$v/classes"
out=$(javac -J-Duser.language=en -d "$v/classes" "$v/$MAIN/journal/AttackOutcome.java" 2>&1); code=$?
expect_failed "$code" "javac без default"
expect_contains "$out" "does not cover all possible input values" "компилятор называет причину"
show "$(grep -m 1 'error' <<<"$out" | sed 's#^.*/##')"

section "Логгер подставляет toString() на место {}"
out=$(run_demo DemoLog); code=$?
expect_ok "$code" "DemoLog"
expect_contains "$out" "настройки: GameDayProperties[length=PT3H, stopWord=red-fox, attackers=2]" \
    "logger.info(\"настройки: {}\", gameDay) выдаёт стоп-слово"
expect_contains "$out" "стоп-слово: StopWord[скрыто]" "StopWord через {} — маска"
show "$(grep -F -e 'настройки:' -e 'стоп-слово:' <<<"$out")"

section "JSON: Jackson берёт value(), а не toString()"
out=$(run_demo DemoJson); code=$?
expect_ok "$code" "DemoJson"
expect_contains "$out" '"value":"red-fox"' "стоп-слово в JSON — методом чтения value()"
expect_not_contains "$out" "скрыто" "маска toString() в JSON не участвует"
show "$out"

section "@ValueSource не обрезает строки: тест без strip() краснеет на трёх строках"
v=$(make_variant no-strip)
sed -i 's/raw\.strip()\.toLowerCase/raw.toLowerCase/' "$v/$MAIN/journal/DutyName.java"
expect_not_contains "$(cat "$v/$MAIN/journal/DutyName.java")" "strip()" "strip() убран из варианта"
out=$(variant_test "$v" -Dtest=DutyNameTest); code=$?
expect_failed "$code" "DutyNameTest без strip()"
expect_regex "$out" "Tests run: 13, Failures: 0, Errors: 3," \
    "до теста дошли \" duty-1 \", \"\\tduty-1\\n\" и \"\\u2003duty-1\" как есть"
show "$(grep -E 'Tests run:.*DutyNameTest|spellingsAreOneName' <<<"$out" | head -n 5)"

section "trim() вместо strip(): краснеет ровно одна строка — с \\u2003"
v=$(make_variant trim)
sed -i 's/raw\.strip()\.toLowerCase/raw.trim().toLowerCase/' "$v/$MAIN/journal/DutyName.java"
expect_contains "$(cat "$v/$MAIN/journal/DutyName.java")" "raw.trim().toLowerCase" "в варианте trim()"
out=$(variant_test "$v" -Dtest=DutyNameTest); code=$?
expect_failed "$code" "DutyNameTest с trim()"
expect_regex "$out" "Tests run: 13, Failures: 0, Errors: 1," "одна ошибка из тринадцати"
show "$(grep -E 'Tests run:.*DutyNameTest|spellingsAreOneName' <<<"$out" | head -n 5)"

section "Без своего toString() тест маски краснеет"
v=$(make_variant no-mask)
perl -0pi -e 's/\n    \@Override\n    public String toString\(\) \{.*?\n    \}\n/\n/s' "$v/$MAIN/StopWord.java"
expect_not_contains "$(cat "$v/$MAIN/StopWord.java")" "toString" "toString() убран из варианта"
out=$(variant_test "$v" -Dtest=StopWordTest); code=$?
expect_failed "$code" "StopWordTest без toString()"
expect_regex "$out" "Tests run: 2, Failures: 1, Errors: 0," "упал hidesValueInsideOtherRecords"
expect_contains "$out" "hidesValueInsideOtherRecords" "имя упавшего теста"
show "$(grep -E 'Tests run:.*StopWordTest|hidesValueInsideOtherRecords' <<<"$out" | head -n 4)"

section "Покрытие: без new DutyName(null) условие в конструкторе жёлтое"
nr=$(grep -n 'value == null || value.isEmpty()' "$MAIN/journal/DutyName.java" | cut -d: -f1)
out=$(jacoco_test -Dtest='DutyNameTest,StopWordTest,AttackOutcomeTest'); code=$?
expect_ok "$code" "тесты статьи под JaCoCo"
[ "$code" -eq 0 ] || show "$(tail -n 30 <<<"$out")"
report=target/site/jacoco/jacoco.xml
expect_file "$report"
read -r _ _ mb cb < <(line_coverage "$report" example/gameday/journal/DutyName.java "$nr")
if [ "${mb:-0}" -gt 0 ] && [ "${cb:-0}" -gt 0 ]; then
    pass "строка $nr жёлтая: веток пройдено $cb, пропущено $mb"
else
    fail "строка $nr: ждали жёлтую, а ветки — пройдено ${cb:-?}, пропущено ${mb:-?}"
fi
note "Покрытие тестов статьи (статья не обещает 100%: «в учебном примере только приёмы»):"
show "$(coverage_summary "$report")"

section "С тестом new DutyName(null) условие зелёное; hasMessageNotContaining есть в AssertJ"
v=$(make_variant more-tests)
perl -0pi -e 's/(import org\.junit\.jupiter\.params\.ParameterizedTest;)/import org.junit.jupiter.api.Test;\n$1/;
    s/\n\}\s*\z/\n\n    \@Test\n    void rejectsNullInConstructor() {\n        assertThatThrownBy(() -> new DutyName(null))\n                .isInstanceOf(IllegalArgumentException.class);\n    }\n}\n/' \
    "$v/$TEST/journal/DutyNameTest.java"
perl -0pi -e 's/\n\}\s*\z/\n\n    \@Test\n    void errorTextHidesValue() {\n        assertThatThrownBy(() -> new StopWord(" red-fox "))\n                .isInstanceOf(IllegalArgumentException.class)\n                .hasMessageNotContaining("red-fox");\n    }\n}\n/' \
    "$v/$TEST/StopWordTest.java"
expect_contains "$(cat "$v/$TEST/journal/DutyNameTest.java")" "new DutyName(null)" "тест добавлен в вариант"
out=$(cd "$v" && jacoco_test -Dtest='DutyNameTest,StopWordTest'); code=$?
expect_ok "$code" "DutyNameTest с new DutyName(null), StopWordTest с hasMessageNotContaining"
[ "$code" -eq 0 ] || show "$(tail -n 30 <<<"$out")"
read -r _ _ mb cb < <(line_coverage "$v/$report" example/gameday/journal/DutyName.java "$nr")
if [ "${mb:-1}" -eq 0 ] && [ "${cb:-0}" -gt 0 ]; then
    pass "строка $nr зелёная: пройдены все $cb веток"
else
    fail "строка $nr: ждали зелёную, а ветки — пройдено ${cb:-?}, пропущено ${mb:-?}"
fi

section "Версии JUnit, AssertJ и Jackson из BOM — для листа сборки"
note "$(mvn -B -ntp dependency:list -DincludeArtifactIds=assertj-core,junit-jupiter-api,jackson-databind 2>&1 \
    | grep -o -E '(org\.assertj|org\.junit\.jupiter|tools\.jackson\.core):[a-z-]+:jar:[0-9.]+' | sort -u | tr '\n' ' ')"
