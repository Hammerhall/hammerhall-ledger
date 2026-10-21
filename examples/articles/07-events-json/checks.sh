# Статья 7 «События: JSON всерьёз» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
# Закрывает лист сборки статьи: пример целиком на Java 25 и BOM Boot 4.1 (это mvn verify),
# getPath и ValueInstantiationException на Jackson из BOM, JSON текстовыми блоками
# в @MethodSource, тексты javac на 25, предупреждение [serial].

EVENTS=src/main/java/example/gameday/events
classpath >/dev/null
DEPS=$(cat target/cp.txt)
PROBE="$VARIANTS/$(basename "$PWD")-probe"

# javac по всем исходникам main варианта — тексты ошибок, как в статье. Код выхода — javac.
javac_variant() {
    local files
    mapfile -t files < <(cd "$1/src/main/java" && find . -name '*.java' -printf '%P\n' | sort)
    (cd "$1/src/main/java" && javac -encoding UTF-8 -proc:none -d "$1/target/javac" -cp "$DEPS" "${files[@]}" 2>&1)
}

# Запись AttackPaused из статьи: $1 — файл, $2 — пакет.
write_paused() {
    mkdir -p "$(dirname "$1")"
    {
        echo "package $2;"
        echo
        [ "$2" = example.gameday.events ] || echo "import example.gameday.events.GameEvent;"
        echo "import java.time.Instant;"
        echo
        echo "public record AttackPaused(Instant at, String target) implements GameEvent {"
        echo "}"
    } >"$1"
}

# Проба: классы статьи, зависимости и эталоны на пути классов.
run_probe() { java "${UTF8[@]}" -cp "$PROBE/classes:target/test-classes:$(classpath)" "$@" 2>&1; }

# В блоке show — только строки пробы с этими началами.
probe_lines() { grep -E "^($1)" <<<"$2"; }

section "Тесты статьи: все случаи таблиц запущены"
for pair in GameEventParserTest:11 GameEventEtalonTest:4; do
    name=${pair%%:*}
    count=${pair##*:}
    suite=$(grep -m 1 -o '<testsuite [^>]*>' "target/surefire-reports/TEST-example.gameday.events.$name.xml" 2>/dev/null)
    expect_contains "$suite" "tests=\"$count\"" "$name: запусков $count (JSON текстовыми блоками в @MethodSource)"
    expect_contains "$suite" 'failures="0"' "$name: без падений"
    expect_contains "$suite" 'errors="0"' "$name: без ошибок"
    expect_contains "$suite" 'skipped="0"' "$name: без пропусков"
done
for file in attack-started attack-stopped unknown-kind version-2; do
    expect_file "target/test-classes/game-day/events/$file.json"
done

section "Версии из BOM Boot 4.1"
mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp-test.txt -Dmdep.includeScope=test >/dev/null
jars=$(tr ':' '\n' <target/cp-test.txt | sed 's#.*/##')
expect_regex "$jars" '^jackson-databind-3\.1\.[0-9]+\.jar$' "статья: «проверено на Jackson 3.1»"
note "$(grep -E '^(jackson-databind|jackson-annotations|junit-jupiter-api|assertj-core)-' <<<"$jars" | tr '\n' ' ')"
note "$(java -version 2>&1 | head -n 1)"

section "Проба Jackson: собрать"
rm -rf "$PROBE" && mkdir -p "$PROBE/src" "$PROBE/classes"
cat >"$PROBE/src/ArticleProbe.java" <<'EOF'
package example.gameday.events;

import java.io.InputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

// Проба для checks.sh статьи 7: печатает то, что статья обещает словами о Jackson 3.
public class ArticleProbe {

    public record PlainStarted(Instant at, String target) {
    }

    static final String EVENT = """
            {"version":1,"kind":"attack_started","at":"2026-10-14T10:00:00Z","target":"feed","note":"кладу двойника"}""";
    static final String YESTERDAY = """
            {"version":1,"kind":"attack_started","at":"вчера","target":"feed"}""";

    static final JsonMapper MAPPER = JsonMapper.builder().build();
    static final Logger LOG = LoggerFactory.getLogger(ArticleProbe.class);

    public static void main(String[] args) throws Exception {
        bind("нет target", """
                {"at":"2026-10-14T10:00:00Z"}""");
        bind("at «вчера»", """
                {"at":"вчера","target":"feed"}""");
        bind("at без зоны", """
                {"at":"2026-10-14T13:00:00","target":"feed"}""");
        bind("лишнее поле note", """
                {"at":"2026-10-14T10:00:00Z","target":"feed","note":"…"}""");
        bind("не JSON", "не json");
        bind("target числом", """
                {"at":"2026-10-14T10:00:00Z","target":5}""");
        bind("at числом", """
                {"at":1760436000,"target":"feed"}""");

        System.out.println("FAIL_ON_UNKNOWN_PROPERTIES по умолчанию: "
                + MAPPER.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
        JsonMapper strict = JsonMapper.builder().enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES).build();
        System.out.println("FAIL_ON_UNKNOWN_PROPERTIES после enable в строителе: "
                + strict.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
        bindTree("строгий маппер, запись без аннотации", strict, PlainStarted.class);
        bindTree("строгий маппер, AttackStarted", strict, AttackStarted.class);

        JsonNode node = MAPPER.readTree("""
                {"kind":"attack_started","target":null,"version":1}""");
        System.out.println("get(\"at\") без поля: " + node.get("at"));
        System.out.println("get(\"target\") при null: isNull() = " + node.get("target").isNull());
        System.out.println("path(\"at\") без поля: " + node.path("at").getClass().getSimpleName());
        JsonNode noVersion = MAPPER.readTree("""
                {"kind":"attack_started"}""");
        System.out.println("path(\"version\").asInt() без версии: " + noVersion.path("version").asInt());
        System.out.println("path(\"target\").asString() без поля: \"" + noVersion.path("target").asString() + "\"");
        try {
            System.out.println("stringValue() у числа: " + node.get("version").stringValue());
        } catch (JacksonException e) {
            System.out.println("stringValue() у числа: " + e.getClass().getSimpleName());
        }

        for (String name : List.of("asText", "textValue", "isTextual", "asString", "stringValue", "isString")) {
            Method method = JsonNode.class.getMethod(name);
            System.out.println("JsonNode." + name + "(): есть, устарел — " + method.isAnnotationPresent(Deprecated.class));
        }
        System.out.println("JsonNode.fields(): " + has(JsonNode.class, "fields"));
        System.out.println("JsonNode.properties(): " + has(JsonNode.class, "properties"));
        System.out.println("ObjectMapper.configure: " + has(ObjectMapper.class, "configure"));
        System.out.println("ObjectMapper.registerModule: " + has(ObjectMapper.class, "registerModule"));
        System.out.println("new ObjectMapper(): " + new ObjectMapper().getClass().getName());

        JsonNode root = MAPPER.readTree(EVENT);
        System.out.println("treeToValue = readValue: "
                + MAPPER.treeToValue(root, AttackStarted.class).equals(MAPPER.readValue(EVENT, AttackStarted.class)));
        try {
            MAPPER.readTree((String) null);
            System.out.println("readTree(null): без исключения");
        } catch (RuntimeException e) {
            System.out.println("readTree(null): " + e.getClass().getSimpleName()
                    + ", JacksonException — " + (e instanceof JacksonException));
        }
        System.out.println("деревья с другим порядком полей и пробелами равны: "
                + MAPPER.readTree("{\"a\":1,\"b\":2}").equals(MAPPER.readTree("{ \"b\" : 2, \"a\":1 }")));

        System.out.println("ресурс /game-day/events/attack-started.json: "
                + found(ArticleProbe.class.getResourceAsStream("/game-day/events/attack-started.json")));
        System.out.println("ресурс game-day/events/attack-started.json: "
                + found(ArticleProbe.class.getResourceAsStream("game-day/events/attack-started.json")));

        System.out.println("--- лог: исключение Jackson причиной");
        try {
            MAPPER.readValue(YESTERDAY, AttackStarted.class);
        } catch (JacksonException e) {
            LOG.error("разбор упал", new IllegalStateException("Событие attack_started: поле at не по договору", e));
        }
        System.out.println("--- лог: исключение разбора");
        try {
            new GameEventParser().parse(YESTERDAY);
        } catch (GameEventParseException e) {
            LOG.error("разбор упал", e);
        }
        System.out.println("--- конец");
    }

    static void bind(String label, String json) {
        try {
            System.out.println(label + ": " + MAPPER.readValue(json, AttackStarted.class));
        } catch (JacksonException e) {
            String cause = e.getCause() == null ? ""
                    : " ← " + e.getCause().getClass().getSimpleName() + ": " + e.getCause().getMessage();
            System.out.println(label + ": " + e.getClass().getSimpleName() + cause
                    + " (JacksonException, RuntimeException — " + (e instanceof RuntimeException) + ")");
            System.out.println(label + ", текст: " + e.getOriginalMessage().lines().findFirst().orElse(""));
        }
    }

    static void bindTree(String label, JsonMapper mapper, Class<?> type) {
        try {
            System.out.println(label + ": " + mapper.treeToValue(mapper.readTree(EVENT), type));
        } catch (JacksonException e) {
            System.out.println(label + ": " + e.getClass().getSimpleName() + ": "
                    + e.getOriginalMessage().lines().findFirst().orElse(""));
        }
    }

    static String has(Class<?> type, String name) {
        return Arrays.stream(type.getMethods()).anyMatch(m -> m.getName().equals(name)) ? "есть" : "нет";
    }

    static String found(InputStream in) {
        return in == null ? "null" : "найден";
    }
}
EOF
cat >"$PROBE/src/BootMapperProbe.java" <<'EOF'
package example.gameday.events;

import example.gameday.GameDayApplication;
import org.springframework.boot.SpringApplication;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.json.JsonMapper;

// Проба для checks.sh статьи 7: бин JsonMapper, который делает Boot в песочнице после статьи 6.
public class BootMapperProbe {

    public static void main(String[] args) {
        try (var context = SpringApplication.run(GameDayApplication.class, args)) {
            JsonMapper mapper = context.getBean(JsonMapper.class);
            System.out.println("бин Boot, FAIL_ON_UNKNOWN_PROPERTIES: "
                    + mapper.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
            ArticleProbe.bindTree("бин Boot, запись без аннотации", mapper, ArticleProbe.PlainStarted.class);
            ArticleProbe.bindTree("бин Boot, AttackStarted", mapper, AttackStarted.class);
        }
    }
}
EOF
out=$(javac -encoding UTF-8 -proc:none -d "$PROBE/classes" -cp "target/classes:$DEPS" "$PROBE"/src/*.java 2>&1)
expect_ok $? "javac пробы"
show "$out"
probe=$(run_probe example.gameday.events.ArticleProbe)
expect_contains "$probe" "--- конец" "проба дошла до конца"
[[ "$probe" == *"--- конец"* ]] || show "$(tail -n 30 <<<"$probe")"

section "Привязка: что бывает, когда JSON не тот (таблица статьи)"
expect_contains "$probe" "нет target: ValueInstantiationException ← IllegalArgumentException: начало атаки: нет цели (target)" \
    "нет target — проверка записи, завёрнутая в ValueInstantiationException"
expect_contains "$probe" "at «вчера»: InvalidFormatException" "\"at\": \"вчера\" — InvalidFormatException"
expect_contains "$probe" "at без зоны: InvalidFormatException" "время без зоны — InvalidFormatException"
expect_contains "$probe" "лишнее поле note: AttackStarted[at=2026-10-14T10:00:00Z, target=feed]" "лишнее поле пропущено"
expect_contains "$probe" "не JSON: StreamReadException" "не JSON — StreamReadException"
expect_not_contains "$probe" "RuntimeException — false" "все — JacksonException, непроверяемые"
show "$(probe_lines 'нет target:|at «вчера»:|at без зоны:|лишнее поле note:|не JSON:' "$probe")"

section "💡 Привязка снисходительна"
expect_contains "$probe" "target числом: AttackStarted[at=2026-10-14T10:00:00Z, target=5]" "\"target\": 5 — строка \"5\""
expect_contains "$probe" "at числом: AttackStarted[at=2025-10-14T10:00:00Z, target=feed]" "\"at\": 1760436000 — секунды от 1970"
show "$(probe_lines 'target числом|at числом' "$probe")"

section "⚠️ Jackson цитирует присланное"
# shellcheck disable=SC2016  # обратные кавычки — часть текста Jackson
expect_contains "$probe" 'at «вчера», текст: Cannot deserialize value of type `java.time.Instant` from String "вчера"' \
    "текст InvalidFormatException — как в статье"
expect_contains "$probe" "не JSON, текст: Unrecognized token 'не'" "текст StreamReadException — как в «Пример целиком»"
show "$(probe_lines 'at «вчера», текст|не JSON, текст' "$probe")"

section "⚠️ Лишние поля: умолчание Jackson 3 и строитель"
expect_contains "$probe" "FAIL_ON_UNKNOWN_PROPERTIES по умолчанию: false" "в Jackson 3 умолчание обратное"
expect_contains "$probe" "FAIL_ON_UNKNOWN_PROPERTIES после enable в строителе: true" "включают одной строкой в строителе"
expect_contains "$probe" 'строгий маппер, запись без аннотации: UnrecognizedPropertyException: Unrecognized property "version"' \
    "без аннотации падает даже правильное событие"
expect_contains "$probe" "строгий маппер, AttackStarted: AttackStarted[at=2026-10-14T10:00:00Z, target=feed]" \
    "@JsonIgnoreProperties держит правило при строгом маппере"
show "$(probe_lines 'FAIL_ON|строгий' "$probe")"

section "Бин JsonMapper от Boot: умолчание и ключ spring.jackson.*"
# С статьи 3а песочница без базы не стартует — проба поднимает Postgres, как часть 1 статьи 3а.
PROBE_DB=game-day-probe-db
docker rm -f "$PROBE_DB" >/dev/null 2>&1
docker run -d --rm --name "$PROBE_DB" -p 127.0.0.1:55432:5432 -e POSTGRES_PASSWORD=probe postgres:17-alpine >/dev/null
for _ in $(seq 90); do
    docker exec "$PROBE_DB" pg_isready -q -h 127.0.0.1 -U postgres && break
    sleep 1
done
# Веб не выключаем: охране из статьи 5 нужен бин HttpSecurity, его Boot даёт веб-приложению.
BOOT_ARGS=(--server.port=0 --spring.main.banner-mode=off
    --spring.datasource.url=jdbc:postgresql://127.0.0.1:55432/postgres
    --spring.datasource.username=postgres --spring.datasource.password=probe)
out=$(run_probe example.gameday.events.BootMapperProbe "${BOOT_ARGS[@]}"); code=$?
expect_ok "$code" "контекст песочницы с бином JsonMapper"
expect_contains "$out" "бин Boot, FAIL_ON_UNKNOWN_PROPERTIES: false" "Boot 4.1 умолчание Jackson 3 не меняет"
expect_contains "$out" "бин Boot, запись без аннотации: PlainStarted[" "бин Boot пропускает лишние поля"
show "$(probe_lines 'бин Boot' "$out")"
[ "$code" -eq 0 ] || show "$(tail -n 30 <<<"$out")"
out=$(run_probe example.gameday.events.BootMapperProbe "${BOOT_ARGS[@]}" \
    --spring.jackson.deserialization.fail-on-unknown-properties=true); code=$?
expect_ok "$code" "контекст с fail-on-unknown-properties=true"
expect_contains "$out" "бин Boot, FAIL_ON_UNKNOWN_PROPERTIES: true" "ключ spring.jackson.deserialization.fail-on-unknown-properties включает строгость"
expect_contains "$out" 'бин Boot, запись без аннотации: UnrecognizedPropertyException: Unrecognized property "version"' \
    "общий бин со строгостью роняет событие без аннотации"
expect_contains "$out" "бин Boot, AttackStarted: AttackStarted[at=2026-10-14T10:00:00Z, target=feed]" \
    "с аннотацией — разбирается"
show "$(probe_lines 'бин Boot' "$out")"
docker rm -f "$PROBE_DB" >/dev/null 2>&1

section "Дерево: get, path, «приведи как сможешь»"
expect_contains "$probe" 'get("at") без поля: null' "get без поля — null"
expect_contains "$probe" 'get("target") при null: isNull() = true' "поле с null — узел, isNull() истинно"
expect_contains "$probe" 'path("at") без поля: MissingNode' "path без поля — MissingNode"
expect_contains "$probe" 'path("version").asInt() без версии: 0' "asInt() на отсутствующем — 0"
expect_contains "$probe" 'path("target").asString() без поля: ""' "asString() на отсутствующем — пустая строка"
expect_contains "$probe" "stringValue() у числа: JsonNodeException" "строка у числа — JsonNodeException"
show "$(probe_lines 'get\(|path\(|stringValue\(\) у' "$probe")"

section "⚠️ Имена Jackson 2 в Jackson 3"
for name in asText textValue isTextual; do
    expect_contains "$probe" "JsonNode.$name(): есть, устарел — true" "$name() работает, но устарел"
done
for name in asString stringValue isString; do
    expect_contains "$probe" "JsonNode.$name(): есть, устарел — false" "$name() — новое имя"
done
expect_contains "$probe" "JsonNode.fields(): нет" "fields() удалён"
expect_contains "$probe" "JsonNode.properties(): есть" "properties() на его месте"
expect_contains "$probe" "ObjectMapper.configure: нет" "у ObjectMapper нет configure"
expect_contains "$probe" "ObjectMapper.registerModule: нет" "у ObjectMapper нет registerModule"
expect_contains "$probe" "new ObjectMapper(): tools.jackson.databind.ObjectMapper" "класс ObjectMapper в Jackson 3 есть"

section "treeToValue, readTree(null), равенство деревьев"
expect_contains "$probe" "treeToValue = readValue: true" "treeToValue — по тем же правилам, что readValue"
expect_contains "$probe" "readTree(null): IllegalArgumentException, JacksonException — false" \
    "readTree(null) — IllegalArgumentException, поэтому null проверяют до него"
expect_contains "$probe" "деревья с другим порядком полей и пробелами равны: true" "💡 readTree(…).equals(…) не смотрит на порядок и отступы"
show "$(probe_lines 'treeToValue|readTree|деревья' "$probe")"

section "Эталон на пути классов"
expect_contains "$probe" "ресурс /game-day/events/attack-started.json: найден" "с / в начале — от корня пути классов"
expect_contains "$probe" "ресурс game-day/events/attack-started.json: null" "без / — от пакета класса, файла нет, null"
show "$(probe_lines 'ресурс' "$probe")"

section "🔴 Причина везёт присланное в лог, своё исключение — нет"
with_cause=$(sed -n '/^--- лог: исключение Jackson причиной/,/^--- лог: исключение разбора/p' <<<"$probe")
without_cause=$(sed -n '/^--- лог: исключение разбора/,/^--- конец/p' <<<"$probe")
expect_contains "$with_cause" "Caused by: tools.jackson.databind.exc.InvalidFormatException" "лог печатает причину строкой Caused by"
expect_contains "$with_cause" "вчера" "через причину «вчера» доехало в лог"
expect_contains "$without_cause" "GameEventParseException: Событие attack_started: поле at не по договору" "в логе — текст разбора"
expect_not_contains "$without_cause" "Caused by:" "у исключения разбора причины нет"
expect_not_contains "$without_cause" "вчера" "присланное в лог не попало"
show "$(grep -E 'IllegalStateException|^Caused by' <<<"$with_cause")"
show "$(grep -E 'GameEventParseException' <<<"$without_cause")"

section "javac: запись вне permits"
v=$(make_variant paused-outside)
write_paused "$v/$EVENTS/AttackPaused.java" example.gameday.events
out=$(javac_variant "$v"); code=$?
expect_failed "$code" "AttackPaused без места в permits"
expect_contains "$out" "error: class is not allowed to extend sealed class: GameEvent (as it is not listed in its 'permits' clause)" \
    "текст ошибки — как в статье"
show "$(grep 'error:' <<<"$out")"

section "javac: AttackPaused в permits — describe не компилируется"
v=$(make_variant paused-permitted)
write_paused "$v/$EVENTS/AttackPaused.java" example.gameday.events
sed -i 's/permits AttackStarted, AttackStopped, UnknownGameEvent/permits AttackStarted, AttackStopped, AttackPaused, UnknownGameEvent/' \
    "$v/$EVENTS/GameEvent.java"
expect_contains "$(cat "$v/$EVENTS/GameEvent.java")" "AttackPaused, UnknownGameEvent" "AttackPaused вписана в permits"
out=$(javac_variant "$v"); code=$?
expect_failed "$code" "AttackPaused в permits"
expect_contains "$out" "GameEventText.java:12: error: the switch expression does not cover all possible input values" \
    "текст и строка ошибки — как в статье"
expect_not_contains "$out" "GameEventParser.java" "switch разбора по перечислению это не задело"
show "$(grep -v -E '^[0-9]+ errors?$' <<<"$out")"

section "javac: с default новый вид проходит молча"
sed -i 's/case UnknownGameEvent(String kind) -> .*/default -> "что-то другое";/' "$v/$EVENTS/GameEventText.java"
expect_contains "$(cat "$v/$EVENTS/GameEventText.java")" 'default -> "что-то другое";' "последняя ветка заменена на default"
out=$(javac_variant "$v"); code=$?
expect_ok "$code" "AttackPaused в permits, в describe — default"
show "$out"

section "javac: новый код в перечислении ломает switch разбора"
v=$(make_variant new-kind)
sed -i 's/ATTACK_STOPPED("attack_stopped");/ATTACK_STOPPED("attack_stopped"),\n    ATTACK_PAUSED("attack_paused");/' \
    "$v/$EVENTS/GameEventKind.java"
expect_contains "$(cat "$v/$EVENTS/GameEventKind.java")" 'ATTACK_PAUSED("attack_paused");' "в перечислении новый код"
out=$(javac_variant "$v"); code=$?
expect_failed "$code" "ATTACK_PAUSED без ветки в разборе"
expect_regex "$out" 'GameEventParser\.java:[0-9]+: error: the switch expression does not cover all possible input values' \
    "сломался switch в GameEventParser"
show "$(grep 'error:' <<<"$out")"

section "javac: старый switch-оператор по перечислению на полноту не проверяется"
v=$(make_variant old-switch)
cat >"$v/$EVENTS/OldSwitch.java" <<'EOF'
package example.gameday.events;

class OldSwitch {

    static String name(GameEventKind kind) {
        String name = "незнакомое";
        switch (kind) {
            case ATTACK_STARTED -> name = "начало";
        }
        return name;
    }
}
EOF
out=$(javac_variant "$v"); code=$?
expect_ok "$code" "switch-оператор без ATTACK_STOPPED, со стрелками"
show "$out"

section "javac: вид из другого пакета в permits — нельзя без модулей"
v=$(make_variant other-package)
write_paused "$v/src/main/java/example/gameday/AttackPaused.java" example.gameday
sed -i 's/permits AttackStarted, AttackStopped, UnknownGameEvent/permits AttackStarted, AttackStopped, UnknownGameEvent, example.gameday.AttackPaused/' \
    "$v/$EVENTS/GameEvent.java"
out=$(javac_variant "$v"); code=$?
expect_failed "$code" "AttackPaused в example.gameday"
expect_contains "$out" "cannot extend a sealed class in a different package" "все виды из permits — в пакете интерфейса"
show "$(grep 'error:' <<<"$out")"

section "javac -Xlint:all: предупреждения кода статьи"
out=$(javac -encoding UTF-8 -proc:none -Xlint:all -d "$PROBE/xlint" -cp "$DEPS" "$EVENTS"/*.java 2>&1); code=$?
expect_ok "$code" "javac -Xlint:all"
if grep -q '\[serial\]' <<<"$out"; then
    note "[serial] у GameEventParseException есть: со сборкой -Werror он её уронит; в песочнице -Werror нет"
else
    note "[serial] нет"
fi
show "$(grep 'warning:' <<<"$out")"
