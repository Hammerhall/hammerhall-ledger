# Статья 16а «Задание без человека» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.
#
# Песочница — после статьи 16: журнал в example.gameday.journal (18 файлов, 2 миграции), сторожа GameDayRulesTest
# (43 запуска), модель статей 12–16 в example.crm и её тесты. Код статьи — клиент системы клуба ClubClient и два
# исключения в src/main/java/example/crm, ClubClientTest в src/test/java/example/crm; pom.xml песочницы прежний.
# В mvn verify тест уже прошёл. Здесь — то, что статья обещает словами: 21 запуск и прежние числа у тестов 12–16;
# из Spring у клиента — только RestClient; короткие куски частей 1, 3 и 4 — те же, что в «Пример целиком», куски
# статьи 15 — как в статье 15; имена строк из named(…) в дереве тестов; вывод Surefire без строки defaultHeader;
# «что будет, если» — мутации ClubClient: какой тест краснеет; двойник WireMock без раздела headers пускает запрос
# без пропуска, с разделом — 404, со вторым правилом пониже приоритетом — 401; стартер restclient приносит
# автонастройку RestClient; первоисточники открываются.
# Мутации гоняются ConsoleLauncher JUnit той же версии, что в BOM Boot, — как в 12–16.

CLS=example.crm.ClubClientTest
CRM=src/main/java/example/crm
CRM_TEST=src/test/java/example/crm
CLIENT=$CRM/ClubClient.java
CLIENT_TEST=$CRM_TEST/ClubClientTest.java
HERE=$PWD
ARTICLE=${ROOT:-}/articles/16a-job-without-a-person.md
ARTICLE15=${ROOT:-}/articles/15-sales-rules-in-settings.md
WIREMOCK_VERSION=3.13.1

# Имена строк из jobCalls() и managerCalls() — как в тесте и в статье.
JOB_CALLS='продления: endingWithin(days)
брони: holdsWithin(hours)
предложения: visits(personId)'
MANAGER_CALLS='карточка: visits(cookie, personId)
карточка: membership(cookie, personId)'

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

# Сколько строк дерева с этой подписью и этим знаком. Аргументы: вывод, подпись, знак (✔ или ✘).
count_marked() { grep -cF -- "$2 $3" <<<"$1"; }

# Сколько строк одного теста в дереве с этим знаком: строки — ветки глубже строки метода, до следующего метода.
# Аргументы: вывод, метод, сколько строк, знак (✔ или ✘), пояснение.
expect_rows() {
    local rows
    rows=$(awk -v m="$2(" -v mark=" $4" '
        !on && index($0, m) { on = 1; depth = index($0, "─"); next }
        on && /[├└]─ / { if (index($0, "─") <= depth) exit; if (index($0, mark)) n++ }
        END { print n + 0 }' <<<"$1")
    if [ "$rows" = "$3" ]; then pass "$5"; else fail "$5: строк со знаком $4 — $rows, ждали $3"; fi
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
        "$1/$CRM"/*.java "$1/$CLIENT_TEST" >"$1/javac.log" 2>&1; then
        fail "вариант $(basename "$1"): example.crm не собрался"
        show "$(cat "$1/javac.log")"
        return 1
    fi
}

# ClubClientTest в ConsoleLauncher на классах из $1.
crm_test() {
    java "${UTF8[@]}" -jar "$CONSOLE" execute --disable-banner --disable-ansi-colors \
        --details=tree --details-theme=unicode --class-path "$1:$TEST_DEPS" --select-class "$CLS" 2>&1
}

# Вариант: правка ClubClient (perl), сборка, прогон теста. Вывод — в $OUT, код выхода — в $CODE, папка — в $MUTANT.
# Аргументы: имя варианта, perl-правка, что правили, флаги perl (необязательно).
OUT=""
CODE=0
MUTANT=""
variant() {
    local name=$1 edit=$2 what=$3 flags=${4:--0pi} v
    OUT=""
    CODE=0
    v=$(make_variant "$name")
    MUTANT=$v
    perl "$flags" -e "$edit" "$v/$CLIENT"
    expect_changed "$v/$CLIENT" "$CLIENT" "$what" || return 1
    pass "в варианте: $what"
    compile_crm "$v" || return 1
    OUT=$(crm_test "$v/classes")
    CODE=$?
}

# Блок кода статьи: первый ```<язык> после строки-заголовка; ограда может стоять с отступом (блок в пункте
# списка) — отступ ограды снимается со строк блока. Аргументы: заголовок (начало строки), язык, файл статьи.
article_block() {
    awk -v head="$1" -v lang="$2" 'index($0, head) == 1 { on = 1; next }
        on && !inside && match($0, /^ *```/) && substr($0, RLENGTH + 1) == lang { pad = RLENGTH - 3; inside = 1; next }
        inside && $0 ~ /^ *```$/ { exit }
        inside { print substr($0, pad + 1) }' "${3:-$ARTICLE}"
}

# Каждая непустая строка куска статьи есть в файле. Аргументы: кусок, файл, пояснение.
expect_lines_in() {
    local missing
    missing=$(grep -v '^$' <<<"$1" | grep -vxF -f "$2")
    if [ -n "$1" ] && [ -z "$missing" ]; then pass "$3"; else fail "$3: строк нет в файле"; show "$missing"; fi
}

# Кусок учебной CRM — дословно как в статье 15: каждая строка, кроме подписи «// учебная…» и «// …», без учёта
# отступа. Аргументы: кусок, пояснение.
expect_lines_in_15() {
    local missing
    missing=$(grep -v '^$' <<<"$1" | sed -E 's/^ +//' | grep -vE '^// (учебн|…)' \
        | grep -vxF -f <(sed -E 's/^ +//' "$ARTICLE15"))
    if [ -n "$1" ] && [ -z "$missing" ]; then pass "$2"; else fail "$2: строк нет в статье 15"; show "$missing"; fi
}

section "Тесты статьи и прошлых статей: все зелёные"
suite_ok "$CLS" 21
note "21 запуск ClubClientTest: по три у четырёх тестов заданий, по два у трёх тестов менеджера, три «ключа нет»"
suite_ok example.crm.PaidSweepTest 13
suite_ok example.crm.ReminderPointTest 8
suite_ok example.crm.CheckoutTest 11
suite_ok example.crm.RublesTest 5
suite_ok example.crm.FunnelNumbersTest 13
suite_ok example.crm.TodayListTest 3
suite_ok example.gameday.journal.GameDayRulesTest 43
note "у сторожа статьи 11 по-прежнему 43 запуска: в папку журнала новые классы не попали"
for cls in IncidentLogTest IncidentMetricsTest IncidentTest IncidentLogIT; do
    suite_green "example.gameday.journal.$cls"
done
suite_green example.gameday.PerimeterTest "тест периметра из статьи 5"
suite_green example.gameday.GameDayApplicationTests "контекст поднялся — ClubClient ему не мешает"

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

section "Код статьи — в example.crm; из Spring у клиента — только RestClient"
for file in ClubClient ServiceKeyMissingException ServiceKeyRejectedException; do
    expect_file "$CRM/$file.java"
done
expect_file "$CLIENT_TEST"
src=$(cat "$CLIENT" "$CRM/ServiceKeyMissingException.java" "$CRM/ServiceKeyRejectedException.java")
expect_regex "$(grep -c '^package example.crm;$' <<<"$src")" '^3$' "все три — в example.crm, рядом с корнем example.gameday"
expect_not_contains "$src" "@Component" "…и ни одной аннотации компонента: сканирование Spring их не видит"
spring=$(grep -E '^import org\.springframework' "$CLIENT" | sort)
expect_regex "$(grep -c '' <<<"$spring")" '^3$' "у ClubClient три импорта Spring"
expect_contains "$spring" "import org.springframework.http.HttpHeaders;" "…HttpHeaders"
expect_contains "$spring" "import org.springframework.web.client.HttpClientErrorException;" "…HttpClientErrorException"
expect_contains "$spring" "import org.springframework.web.client.RestClient;" "…RestClient — из веб-стартера статьи 4"
expect_not_contains "$(cat "$CRM/ServiceKeyMissingException.java" "$CRM/ServiceKeyRejectedException.java")" \
    "org.springframework" "исключения — чистая Java"
for file in FollowUp TodayList Discount PriceBreakdown Checkout Rubles ReminderPoint HeldPlace OpenFollowUp PaidSweep; do
    expect_file "$CRM/$file.java"
done
expect_regex "$(find src/main/java/example/gameday/journal -name '*.java' | grep -c '')" '^18$' \
    "в папке журнала по-прежнему 18 файлов — их и обходит сторож статьи 11"
expect_regex "$(find src/main/resources/db/migration -name '*.sql' | grep -c '')" '^2$' "миграций по-прежнему две"
expect_regex "$(grep -rlE 'ClubSystemProperties|pollEndingMemberships|notFoundInRow|EndingMembership' src | grep -c '')" \
    '^0$' "куски учебной CRM в песочницу не попали"
expect_not_contains "$(cat pom.xml)" "spring-boot-starter-restclient" "в pom.xml песочницы стартера restclient нет — ничего не добавляли"
expect_regex "$(tr ':' '\n' <<<"$TEST_DEPS" | grep -c 'spring-boot-restclient-')" '^0$' \
    "модуля spring-boot-restclient на classpath нет: бина RestClient.Builder в контексте песочницы нет, тест строит его сам"

section "Короткие куски — те же, что в «Пример целиком»; куски статьи 15 — как в статье 15"
if [ ! -f "$ARTICLE" ]; then
    fail "нет текста статьи: $ARTICLE"
else
    short=$(article_block "передаёт её системе клуба как есть" java)
    expect_contains "$short" "public String visits(String sessionCookie, UUID personId)" "в части 1 — метод менеджера"
    expect_lines_in "$short" "$CLIENT" "каждая строка метода менеджера — в ClubClient «Пример целиком»"
    short=$(article_block "Главная правка — в конструкторе" java)
    expect_contains "$short" "public ClubClient(RestClient.Builder builder, String baseUrl, String serviceKey)" \
        "в части 3 — конструктор"
    expect_contains "$short" ".defaultHeader(HttpHeaders.AUTHORIZATION" "…с defaultHeader"
    expect_lines_in "$short" "$CLIENT" "каждая строка конструктора — в ClubClient"
    short=$(article_block "Все три метода заданий идут через один вход:" java)
    expect_contains "$short" "private String serviceCall(Function<RestClient, String> request)" "в части 3 — serviceCall"
    expect_lines_in "$short" "$CLIENT" "каждая строка serviceCall — в ClubClient"
    short=$(article_block "А сам метод задания стал таким:" java)
    expect_contains "$short" "public String endingWithin(int days)" "в части 3 — endingWithin"
    expect_lines_in "$short" "$CLIENT" "каждая строка endingWithin — в ClubClient"
    short=$(article_block "* **Как запускается.** Тест поднимает его" java)
    expect_contains "$short" "void startServer() throws IOException" "в части 4 — сервер теста"
    expect_lines_in "$short" "$CLIENT_TEST" "каждая строка startServer — в ClubClientTest"
    short=$(article_block "Вызовы собраны в два списка" java)
    expect_contains "$short" "static Stream<Named<Consumer<ClubClient>>> jobCalls()" "в части 4 — список заданий"
    expect_lines_in "$short" "$CLIENT_TEST" "каждая строка jobCalls — в ClubClientTest"
    short=$(article_block "Тест по таблице (статья 0)" java)
    expect_contains "$short" "void jobCall_sendsServiceKeyAndNoCookie" "в части 4 — тест «ключ уходит»"
    expect_lines_in "$short" "$CLIENT_TEST" "каждая его строка — в ClubClientTest"
    short=$(article_block "### Без ключа — ни одного запроса" java)
    expect_contains "$short" "void jobCall_withoutKey_failsBeforeNetwork" "в части 4 — тест «без ключа»"
    expect_lines_in "$short" "$CLIENT_TEST" "каждая его строка — в ClubClientTest"
    expect_contains "$(cat "$CLIENT_TEST")" "import static org.junit.jupiter.api.Named.named;" \
        "named(…) — из JUnit, как в статье 11"
    rejected=$(sed -nE 's/.*super\("([^"]*)", cause\);.*/\1/p' "$CRM/ServiceKeyRejectedException.java")
    expect_contains "$(tr '\n' ' ' <"$ARTICLE" | tr -s ' ')" "«$rejected»" \
        "сообщение ServiceKeyRejectedException в статье — то же, что в коде: «$rejected»"

    if [ ! -f "$ARTICLE15" ]; then
        fail "нет текста статьи 15: $ARTICLE15"
    else
        expect_lines_in_15 "$(article_block "Обход продлений ты видел в статье 15" java)" \
            "часть 1: @Scheduled и вызов обхода продлений — как в статье 15"
        expect_lines_in_15 "$(article_block "4. Срабатывает тот самый" java)" "часть 2: catch обхода — как в статье 15"
        expect_lines_in_15 "$(article_block "Тест обхода из статьи 15 подменяет клиента" java)" \
            "часть 2: заглушка клиента — как в статье 15"
    fi
fi

section "21 запуск в ConsoleLauncher; у строк — имена из named(…)"
out=$(crm_test "$HERE/target/test-classes:$HERE/target/classes"); code=$?
expect_ok "$code" "ConsoleLauncher: ClubClientTest на песочнице"
expect_summary "$out" 0 0 "ClubClientTest"
expect_regex "$(summary_of "$out" 'tests successful')" '^21$' "зелёных 21"
while IFS= read -r name; do
    expect_regex "$(count_marked "$out" "$name" ✔)" '^4$' "«$name» — зелёная строка у каждого из четырёх тестов заданий"
done <<<"$JOB_CALLS"
while IFS= read -r name; do
    expect_regex "$(count_marked "$out" "$name" ✔)" '^3$' "«$name» — зелёная строка у каждого из трёх тестов менеджера"
done <<<"$MANAGER_CALLS"
expect_not_contains "$out" "[2] ✔" "в дереве не номера строк, а имена"
show "$(grep -E '✔|✘' <<<"$out" | grep -vE 'JUnit|ClubClientTest ')"

section "Тест умеет краснеть: без строки defaultHeader — вывод Surefire из части 4"
NOHEADER='s/\n\s*\.defaultHeader\(HttpHeaders\.AUTHORIZATION, "Bearer " \+ serviceKey\.strip\(\)\)//'
if variant noheader "$NOHEADER" "из конструктора убрана строка defaultHeader"; then
    expect_failed "$CODE" "ConsoleLauncher без defaultHeader"
    expect_summary "$OUT" 3 0 "ConsoleLauncher без defaultHeader"
    expect_rows "$OUT" jobCall_sendsServiceKeyAndNoCookie 3 ✘ "красные все три строки jobCall_sendsServiceKeyAndNoCookie"
    for method in managerCall_sendsCookieAndNoServiceKey jobCall_withoutKey_failsBeforeNetwork \
        managerCall_withoutKey_stillWorks jobCall_on401_saysKeyRejected jobCall_on404_staysNotFound \
        managerCall_on401_staysUnauthorized blankKey_meansNoKey; do
        expect_rows "$OUT" "$method" 0 ✘ "$method — ни одной красной строки"
    done
    sure=$(cd "$MUTANT" && mvn -B -ntp test -Dtest=ClubClientTest 2>&1)
    expect_failed $? "mvn test без defaultHeader"
    printed=$(article_block "Убери из конструктора одну строку" "")
    expect_contains "$printed" "Tests run: 21, Failures: 3" "в статье — 21 запуск и три красных"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        expect_contains "$sure" "$line" "строка вывода из статьи есть в выводе Surefire: «$line»"
    done <<<"$printed"
fi

section "Что будет, если: клиент заданий собран из builder первым, клиент менеджера — после"
ORDER='s/this\.http = builder\n\s*\.baseUrl\(baseUrl\)\n\s*\.build\(\);\n(\s*)if \(serviceKey == null \|\| serviceKey\.isBlank\(\)\) \{\n\s*this\.serviceHttp = null;\n\s*\} else \{\n\s*\/\/[^\n]*\n\s*this\.serviceHttp = http\.mutate\(\)/builder.baseUrl(baseUrl);\n$1if (serviceKey == null || serviceKey.isBlank()) {\n            this.serviceHttp = null;\n        } else {\n            this.serviceHttp = builder/; s/(\.build\(\);\n        \}\n)/$1        this.http = builder.build();\n/'
if variant order "$ORDER" "сначала клиент заданий из builder, потом клиент менеджера из того же builder"; then
    expect_failed "$CODE" "строитель помнит ключ"
    expect_summary "$OUT" 2 0 "строитель помнит ключ"
    expect_rows "$OUT" managerCall_sendsCookieAndNoServiceKey 2 ✘ "красные оба запуска managerCall_sendsCookieAndNoServiceKey"
    expect_contains "$(grep -A 4 '✘' <<<"$OUT")" "Bearer test-service-key" "в отчёте — ключ, прилипший к менеджеру"
fi

section "Что будет, если: без проверки serviceHttp == null — без ключа берут клиент менеджера"
NOGUARD='s/if \(serviceHttp == null\) \{\n\s*throw new ServiceKeyMissingException\(\);\n\s*\}\n\s*try \{\n\s*return request\.apply\(serviceHttp\);/try {\n            return request.apply(serviceHttp != null ? serviceHttp : http);/'
if variant noguard "$NOGUARD" "serviceCall без проверки ключа"; then
    expect_failed "$CODE" "без проверки ключа"
    expect_summary "$OUT" 3 0 "без проверки ключа"
    expect_rows "$OUT" jobCall_withoutKey_failsBeforeNetwork 3 ✘ "красные три запуска jobCall_withoutKey_failsBeforeNetwork"
fi

section "Что будет, если: без catch на 401"
NO401='s/try \{\n\s*return request\.apply\(serviceHttp\);\n\s*\} catch \(HttpClientErrorException\.Unauthorized e\) \{\n\s*throw new ServiceKeyRejectedException\(e\);\n\s*\}/return request.apply(serviceHttp);/'
if variant no401 "$NO401" "serviceCall без catch на 401"; then
    expect_failed "$CODE" "без catch на 401"
    expect_summary "$OUT" 3 0 "без catch на 401"
    expect_rows "$OUT" jobCall_on401_saysKeyRejected 3 ✘ "красные три запуска jobCall_on401_saysKeyRejected"
fi

section "Двойник: правило без раздела headers пускает запрос без пропуска — WireMock"
WM=$VARIANTS/$(basename "$PWD")-wiremock
rm -rf "$WM" && mkdir -p "$WM/mappings" "$WM/__files"
out=$(mvn -B -q -ntp dependency:copy -Dartifact="org.wiremock:wiremock-standalone:$WIREMOCK_VERSION" \
    -DoutputDirectory="$WM" 2>&1)
expect_ok $? "WireMock $WIREMOCK_VERSION скачан"
rule=$(article_block "Правило двойника для продлений:" json)
expect_contains "$rule" '"urlPath": "/club/memberships/ending"' "правило из статьи — путь продлений"
expect_not_contains "$rule" '"Authorization"' "…и ни слова о заголовке Authorization"
printf '%s\n' "$rule" >"$WM/mappings/ending.json"
echo '[]' >"$WM/__files/ending.json"
PORT=$((20000 + RANDOM % 20000))
java -jar "$WM/wiremock-standalone-$WIREMOCK_VERSION.jar" --port "$PORT" --root-dir "$WM" >"$WM/wiremock.log" 2>&1 &
WM_PID=$!
if wait_http "http://127.0.0.1:$PORT/__admin/mappings" 60 >/dev/null; then
    URL="http://127.0.0.1:$PORT/club/memberships/ending?within-days=14"
    expect_regex "$(curl -s -o /dev/null -w '%{http_code}' "$URL")" '^200$' "без пропуска — 200: анонимный запрос пройдёт"
    expect_regex "$(curl -s -o /dev/null -w '%{http_code}' -H 'Cookie: SESSION=x' "$URL")" '^200$' "с кукой — 200"
    expect_regex "$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer x' "$URL")" '^200$' "с ключом — 200"
    expect_regex "$(curl -s "$URL")" '^\[\]$' "тело — JSON из файла ending.json"
    # Раздел headers: правило требует ключ — запрос без пропуска уже не подходит.
    strict=$(python3 -c 'import json, sys
rule = json.loads(sys.stdin.read())
rule["request"]["headers"] = {"Authorization": {"matches": "Bearer .+"}}
print(json.dumps(rule))' <<<"$rule")
    curl -s -o /dev/null -X DELETE "http://127.0.0.1:$PORT/__admin/mappings"
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST --data "$strict" "http://127.0.0.1:$PORT/__admin/mappings")
    expect_regex "$code" '^201$' "правило с разделом headers принято"
    expect_regex "$(curl -s -o /dev/null -w '%{http_code}' "$URL")" '^404$' "с разделом headers без пропуска — 404: правило не подошло"
    expect_regex "$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer x' "$URL")" '^200$' \
        "с разделом headers и ключом — 200"
    # 💡 части 4: второе правило на тот же путь — без headers, с приоритетом пониже — отвечает 401.
    tip=$(tr '\n' ' ' <"$ARTICLE" | tr -s ' ')
    expect_contains "$tip" "WireMock отвечает \`404\`" "в 💡 — несовпавший запрос получает 404"
    expect_contains "$tip" "\`priority\`: чем больше число, тем ниже приоритет" "в 💡 — поле priority"
    rest=$(python3 -c 'import json, sys
rule = json.loads(sys.stdin.read())
rule["priority"] = 10
rule["response"] = {"status": 401}
print(json.dumps(rule))' <<<"$rule")
    first=$(python3 -c 'import json, sys
rule = json.loads(sys.stdin.read())
rule["priority"] = 1
print(json.dumps(rule))' <<<"$strict")
    curl -s -o /dev/null -X DELETE "http://127.0.0.1:$PORT/__admin/mappings"
    curl -s -o /dev/null -X POST --data "$first" "http://127.0.0.1:$PORT/__admin/mappings"
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST --data "$rest" "http://127.0.0.1:$PORT/__admin/mappings")
    expect_regex "$code" '^201$' "второе правило — тот же путь, priority 10, ответ 401 — принято"
    expect_regex "$(curl -s -o /dev/null -w '%{http_code}' "$URL")" '^401$' "два правила: без пропуска — 401, как у системы клуба"
    expect_regex "$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer x' "$URL")" '^200$' \
        "два правила: с ключом — 200"
else
    fail "WireMock не поднялся за 60 с"
    show "$(tail -n 20 "$WM/wiremock.log")"
fi
kill "$WM_PID" 2>/dev/null
wait "$WM_PID" 2>/dev/null

section "⚠️ Boot 4: автонастройку RestClient приносит стартер restclient"
RC=$(make_variant restclient)
perl -0pi -e 's#(<dependencies>)#$1\n        <dependency>\n            <groupId>org.springframework.boot</groupId>\n            <artifactId>spring-boot-starter-restclient</artifactId>\n        </dependency>#' \
    "$RC/pom.xml"
expect_contains "$(cat "$RC/pom.xml")" "spring-boot-starter-restclient" "в варианте в pom.xml — стартер restclient"
(cd "$RC" && mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=cp.txt -Dmdep.includeScope=runtime >/dev/null 2>&1)
jar=$(tr ':' '\n' <"$RC/cp.txt" | grep 'spring-boot-restclient-' | head -n 1)
if [ -n "$jar" ]; then
    pass "стартер принёс модуль $(basename "$jar")"
    imports=$(unzip -p "$jar" META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports)
    expect_contains "$imports" "RestClientAutoConfiguration" "в модуле — RestClientAutoConfiguration: она и даёт бин RestClient.Builder"
else
    fail "стартер restclient не принёс spring-boot-restclient"
fi

section "Первоисточники открываются"
for link in https://docs.spring.io/spring-boot/4.0/reference/io/rest-client.html \
    https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/client/RestClient.html \
    https://www.rfc-editor.org/rfc/rfc6750 \
    https://wiremock.org/docs/request-matching/ \
    https://docs.oracle.com/en/java/javase/25/docs/api/jdk.httpserver/com/sun/net/httpserver/HttpServer.html; do
    status=$(curl -sSL --retry 3 -m 30 -o /dev/null -w '%{http_code}' "$link" 2>/dev/null); code=$?
    if [ "$code" -ne 0 ]; then
        note "не проверено, сеть: curl $code — $link"
    elif [ "$status" -lt 400 ]; then
        pass "$status — $link"
    else
        fail "$status — $link"
    fi
done
