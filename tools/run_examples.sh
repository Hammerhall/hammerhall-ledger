#!/usr/bin/env bash
# Собирает примеры статей и проверяет то, что статьи обещают словами.
# Сначала разложить примеры: python3 tools/extract_examples.py
# Запуск из корня репозитория: bash tools/run_examples.sh — все разложенные примеры;
# bash tools/run_examples.sh articles/06-stand — только названные. Так зовёт CI: у каждого примера
# своя задача, и красный пример не красит задачи тех, что стоят на нём, — их base только раскладывается.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="${EXAMPLES_BUILD:-$ROOT/build/examples}"
export VARIANTS="$ROOT/build/variants"
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}

if [ ! -d "$BUILD" ]; then
    echo "Нет $BUILD — сначала: python3 tools/extract_examples.py" >&2
    exit 2
fi

poms=()
if [ "$#" -gt 0 ]; then
    for name in "$@"; do
        if [ ! -f "$BUILD/$name/pom.xml" ]; then
            echo "Нет $BUILD/$name/pom.xml — сначала: python3 tools/extract_examples.py $name" >&2
            exit 2
        fi
        poms+=("$BUILD/$name/pom.xml")
    done
else
    mapfile -t poms < <(find "$BUILD" -name pom.xml -not -path '*/target/*' | sort)
fi

failed=0
echo "## Примеры статей" >>"$SUMMARY"

for pom in "${poms[@]}"; do
    dir=$(dirname "$pom")
    name=${dir#"$BUILD"/}
    echo
    echo "═══ $name"
    printf '\n### %s\n\n' "$name" >>"$SUMMARY"

    if (cd "$dir" && mvn -B -ntp verify); then
        echo "- ✅ mvn verify" >>"$SUMMARY"
    else
        echo "- ❌ mvn verify" >>"$SUMMARY"
        failed=$((failed + 1))
        continue
    fi

    if [ -f "$dir/checks.sh" ]; then
        # shellcheck disable=SC1091
        (cd "$dir" && source "$ROOT/tools/checks_lib.sh" && source ./checks.sh && exit "$FAILED")
        failed=$((failed + $?))
    fi
done

echo
if [ "$failed" -eq 0 ]; then
    echo "Все примеры собраны, обещания статей выполнены."
    printf '\n**Итог: зелёный.**\n' >>"$SUMMARY"
else
    echo "Не выполнено проверок: $failed"
    printf '\n**Итог: не выполнено проверок — %s.**\n' "$failed" >>"$SUMMARY"
    exit 1
fi
