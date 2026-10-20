# Статья 0 «Что нужно знать до Spring» — утверждения статьи, которые проверяет прогон.
# Запускает tools/run_examples.sh из папки собранного примера; функции — tools/checks_lib.sh.

section "Отчёт JaCoCo там, где обещает статья"
expect_file "target/site/jacoco/index.html"

section "Без теста rejectsZero покрытие не 100% — сборка красная"
v=$(make_variant no-reject-zero)
perl -0pi -e 's/\n    \@Test\n    void rejectsZero\(\) \{.*?\n    \}\n/\n/s' "$v/src/test/java/example/TaskKeyTest.java"
expect_not_contains "$(cat "$v/src/test/java/example/TaskKeyTest.java")" "rejectsZero" "тест убран из варианта"
out=$(cd "$v" && mvn -B -ntp verify 2>&1); code=$?
expect_failed "$code" "verify без rejectsZero"
expect_contains "$out" "Rule violated" "JaCoCo называет нарушенное правило"
show "$(grep -E 'Rule violated|covered ratio' <<<"$out")"
