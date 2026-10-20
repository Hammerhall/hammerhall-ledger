# Общие функции для examples/**/checks.sh. Подключает tools/run_examples.sh;
# каждая проверка пишет строку в лог и в сводку прогона GitHub Actions.
# shellcheck shell=bash

FAILED=0
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
UTF8=(-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8)

section() { echo; echo "── $1"; printf '\n#### %s\n\n' "$1" >>"$SUMMARY"; }
pass()    { echo "  ✅ $1"; printf -- '- ✅ %s\n' "$1" >>"$SUMMARY"; }
fail()    { echo "  ❌ $1"; printf -- '- ❌ %s\n' "$1" >>"$SUMMARY"; FAILED=$((FAILED + 1)); }
note()    { echo "  ℹ️  $1"; printf -- '- ℹ️ %s\n' "$1" >>"$SUMMARY"; }

# Показать вывод программы: в лог и в сводку — кусок, который пойдёт в статью.
show() {
    [ -z "$1" ] && return 0
    sed 's/^/    │ /' <<<"$1"
    { echo; echo '```'; echo "$1"; echo '```'; } >>"$SUMMARY"
}

expect_ok()           { if [ "$1" -eq 0 ]; then pass "$2: код выхода 0"; else fail "$2: код выхода $1, ждали 0"; fi; }
expect_failed()       { if [ "$1" -ne 0 ]; then pass "$2: упало, как обещает статья (код $1)"; else fail "$2: не упало, а статья обещает ошибку"; fi; }
expect_contains()     { if grep -qF -- "$2" <<<"$1"; then pass "$3"; else fail "$3: нет «$2»"; fi; }
expect_not_contains() { if grep -qF -- "$2" <<<"$1"; then fail "$3: есть «$2»"; else pass "$3"; fi; }
expect_regex()        { if LC_ALL=C.UTF-8 grep -qE -- "$2" <<<"$1"; then pass "$3"; else fail "$3: не совпало с /$2/"; fi; }
expect_file()         { if [ -f "$1" ]; then pass "есть $1"; else fail "нет $1"; fi; }

# Классы проекта и его зависимости — чтобы запустить main без Boot, как в статье.
classpath() {
    if [ ! -f target/cp.txt ]; then
        mvn -B -q -ntp dependency:build-classpath -Dmdep.outputFile=target/cp.txt -Dmdep.includeScope=runtime >/dev/null
    fi
    echo "target/classes:$(cat target/cp.txt)"
}

run_main() { local cls=$1; shift; java "${UTF8[@]}" -cp "$(classpath)" "$cls" "$@" 2>&1; }
run_jar()  { local jar=$1; shift; java "${UTF8[@]}" -jar "$jar" "$@" 2>&1; }

# Копия собранного примера без target — для «что будет, если…». Печатает путь.
make_variant() {
    local dir
    dir="$VARIANTS/$(basename "$PWD")-$1"
    rm -rf "$dir" && mkdir -p "$dir"
    tar --exclude=./target --exclude=./checks.sh -cf - . | tar -xf - -C "$dir"
    echo "$dir"
}

# Ждать, пока адрес ответит 2xx; печатает ответ. Код 1 — не дождались.
wait_http() {
    local url=$1 seconds=${2:-60} i
    for ((i = 0; i < seconds; i++)); do
        if curl -fsS "$url" 2>/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

compile_variant() {
    if ! (cd "$1" && mvn -B -q -ntp compile) >/dev/null 2>&1; then
        fail "вариант $(basename "$1") не скомпилировался"
    fi
}
