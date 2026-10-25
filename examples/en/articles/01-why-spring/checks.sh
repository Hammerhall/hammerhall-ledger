# Английская редакция статьи 1 (en/articles/01-why-spring.md) — те же проверки, что у русской,
# со строками программы по-английски.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.

LINE_RE='^\[notification\] duty-1: Broker is not responding — detected at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$'

section "HandMadeApp: сборка руками в main"
out=$(run_main example.gameday.journal.HandMadeApp); code=$?
expect_ok "$code" "HandMadeApp"
expect_regex "$out" "$LINE_RE" "строка оповещения"
show "$out"

section "GameDayApp: контейнер собрал те же объекты"
out=$(run_main example.gameday.journal.GameDayApp); code=$?
expect_ok "$code" "GameDayApp"
expect_regex "$(tail -n 1 <<<"$out")" "$LINE_RE" "последняя строка — оповещение"
note "Строк DEBUG перед оповещением: $(grep -c 'DEBUG' <<<"$out")"
show "$(head -n 5 <<<"$out")"

section "Без бина часов контейнер падает при запуске — текст ошибки для статьи"
v=$(make_variant no-clock)
cat > "$v/src/main/java/example/gameday/journal/GameDayConfig.java" <<'EOF'
package example.gameday.journal;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;

@Configuration
@ComponentScan
public class GameDayConfig {

    @Bean
    public DutyRoster dutyRoster() {
        return new DutyRoster("duty-1");
    }
}
EOF
compile_variant "$v"
out=$(cd "$v" && run_main example.gameday.journal.GameDayApp); code=$?
expect_failed "$code" "GameDayApp без часов"
expect_contains "$out" "'incidentLog'" "имя бина журнала"
expect_contains "$out" "parameter 2" "третий параметр конструктора"
expect_contains "$out" "java.time.Clock" "тип, которого нет"
show "$(grep -m 3 -E 'Error creating bean|Unsatisfied dependency|No qualifying bean' <<<"$out")"

section "Без бина часов падает и GameDayApplicationTests"
out=$(cd "$v" && mvn -B -ntp test 2>&1); code=$?
expect_failed "$code" "mvn test без часов"
expect_contains "$out" "GameDayApplicationTests" "упал тест от Initializr"

section "Два бина Notifier — ошибка при запуске"
v=$(make_variant two-notifiers)
cat > "$v/src/main/java/example/gameday/journal/SecondNotifier.java" <<'EOF'
package example.gameday.journal;

import org.springframework.stereotype.Component;

@Component
public class SecondNotifier implements Notifier {

    @Override
    public void send(String dutyName, String text) {
    }
}
EOF
compile_variant "$v"
out=$(cd "$v" && run_main example.gameday.journal.GameDayApp); code=$?
expect_failed "$code" "GameDayApp с двумя Notifier"
expect_contains "$out" "found 2" "контейнер нашёл два бина"
show "$(grep -m 2 -E 'expected single matching bean|found 2' <<<"$out")"
