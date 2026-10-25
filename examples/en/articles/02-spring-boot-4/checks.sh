# Английская редакция статьи 2 (en/articles/02-spring-boot-4.md) — те же проверки, что у русской,
# со строками программы по-английски.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.

JAR=target/game-day-0.0.1-SNAPSHOT.jar

section "./mvnw package собрал один .jar"
expect_file "$JAR"

section "Запуск без профиля"
out=$(run_jar "$JAR"); code=$?
expect_ok "$code" "java -jar"
expect_contains "$out" "[notification] duty-1: Broker is not responding" "журнал собран Boot"
expect_contains "$out" "game PT3H, attackers 2" "умолчания из записи"
expect_not_contains "$out" "Tomcat started" "веб-сервера в песочнице нет"
show "$(tail -n 3 <<<"$out")"

section "Профиль stand и стоп-слово из окружения"
out=$(GAME_DAY_STOP_WORD=stop run_jar "$JAR" --spring.profiles.active=stand); code=$?
expect_ok "$code" "stand"
expect_contains "$out" "attackers 4" "профильный файл побеждает"

out=$(GAME_DAY_STOP_WORD=stop HAMMERHALL_GAMEDAY_ATTACKERS=6 run_jar "$JAR" --spring.profiles.active=stand); code=$?
expect_ok "$code" "stand + переменная"
expect_contains "$out" "attackers 6" "переменная окружения поверх файлов"

out=$(GAME_DAY_STOP_WORD=stop SPRING_PROFILES_ACTIVE=stand run_jar "$JAR"); code=$?
expect_ok "$code" "профиль переменной"
expect_contains "$out" "attackers 4" "SPRING_PROFILES_ACTIVE=stand — как аргумент"

section "Профиль stand без переменной — старт падает с нашим текстом"
unset GAME_DAY_STOP_WORD
out=$(run_jar "$JAR" --spring.profiles.active=stand); code=$?
expect_failed "$code" "stand без GAME_DAY_STOP_WORD"
expect_contains "$out" "the environment variable was not substituted" "текст компактного конструктора"
show "$(grep -m 2 -E 'was not substituted' <<<"$out")"

section "attackers: 0 — APPLICATION FAILED TO START (вид блока для статьи)"
out=$(run_jar "$JAR" --hammerhall.game-day.attackers=0); code=$?
expect_failed "$code" "attackers=0"
expect_contains "$out" "APPLICATION FAILED TO START" "заголовок блока"
expect_contains "$out" "Property: hammerhall.game-day.attackers" "имя настройки"
expect_contains "$out" 'Value: "0"' "значение"
show "$(grep -A 12 'APPLICATION FAILED TO START' <<<"$out")"

section "Пустое стоп-слово — в блоке имя поля stopWord"
out=$(run_jar "$JAR" --hammerhall.game-day.stop-word=); code=$?
expect_failed "$code" "stop-word пустое"
expect_contains "$out" "stopWord" "статья: «будет stopWord — имя поля в Java»"
show "$(grep -A 12 'APPLICATION FAILED TO START' <<<"$out")"

section "length: 5m — короче 30 минут, старт падает"
out=$(run_jar "$JAR" --hammerhall.game-day.length=5m); code=$?
expect_failed "$code" "length=5m"
expect_contains "$out" "hammerhall.game-day.length" "имя настройки"
