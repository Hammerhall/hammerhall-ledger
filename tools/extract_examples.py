#!/usr/bin/env python3
"""Раскладывает «Пример целиком» статей в проекты Maven.

Для каждой папки examples/<раздел>/<пример>/ с файлом example.json:

    {
      "article": "articles/01-why-spring.md",   # откуда брать код
      "base": "articles/00-before-spring",      # необязательно: проект, на котором стоит этот
      "delete": ["src/main/java/..."]           # необязательно: что убрать из base
    }

Проект собирается в build/examples/<раздел>/<пример>/ так:
  1. копия base (если есть), минус файлы из delete;
  2. файлы самой папки примера, кроме example.json и checks.sh, —
     pom.xml и то, что кладёт start.spring.io;
  3. код из раздела «Пример целиком» статьи — поверх всего.

Блок кода попадает в проект, если его первая строка — путь комментарием:
`// src/...`, `-- src/.../V1__x.sql`, `# compose.yaml`, `# Dockerfile`, `<!-- pom.xml -->`;
после пути может идти пояснение через « — ». Строка пути остаётся
в файле — как у читателя, который копирует блок целиком: номера строк
в ошибках совпадут со статьёй. Не остаётся только в XML (до `<?xml`
комментарий нельзя) и в блоке «— дописать в конец» — такой блок
дописывается к файлу. У скрипта первая строка — shebang, путь — во второй.
Где комментариев нет (JSON), путь пишут строкой текста прямо над блоком:
`` `src/test/resources/x.json`: ``. Кусок файла («pom.xml: в <dependencies>…»)
не берётся: в проекте свой pom.xml.

Английская редакция — то же самое: examples/en/<раздел>/<пример>/example.json
ссылается на en/<раздел>/<файл>.md, раздел кода в ней — «## The full example,
with imports», дописывание — « — append to the end».

Запуск из корня репозитория: python3 tools/extract_examples.py
"""
import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / "examples"
BUILD = Path(os.environ.get("EXAMPLES_BUILD", ROOT / "build" / "examples"))

# Английская редакция (en/…) зовёт раздел «The full example, with imports».
FULL_EXAMPLE = re.compile(r"^## (?:Пример целиком|The full example)")
NEXT_SECTION = re.compile(r"^## ")
FENCE = re.compile(r"^```")
PATH_LINE = re.compile(
    r"^\s*(?://|#|<!--|--)\s*"
    r"(?P<path>Dockerfile|[\w.-]*(?:/[\w.-]+)*\.[\w]+|\.[\w.-]+)"
    r"(?P<rest>\s+—\s+.*?)?\s*(?:-->)?\s*$"
)
APPEND = ("дописать", "append")              # «— дописать в конец» / «— append to the end»
PATH_ABOVE = re.compile(r"^`(?P<path>[\w.-]*(?:/[\w.-]+)*\.\w+)`:\s*$")


def text(lines: list[str]) -> str:
    return "\n".join(lines).rstrip("\n") + "\n"


def file_of(block: list[str], above: str) -> tuple[str, str, bool] | None:
    """(путь, содержимое, дописать ли) — или None, если блок не файл.
    above — последняя непустая строка текста перед блоком."""
    if block and block[0].startswith("#!") and len(block) > 1:
        match = PATH_LINE.match(block[1])
        if match:
            return match.group("path"), text(block), False
        return None
    match = PATH_LINE.match(block[0]) if block else None
    if match:
        path = match.group("path")
        if any(word in (match.group("rest") or "") for word in APPEND):
            return path, text(block[1:]), True
        if path.endswith(".xml") or block[0].lstrip().startswith("<!--"):
            return path, text(block[1:]), False
        return path, text(block), False
    match = PATH_ABOVE.match(above)
    if match:
        return match.group("path"), text(block), False
    return None


def full_example_files(article: Path) -> dict[str, tuple[str, bool]]:
    """Файлы из раздела «Пример целиком»: путь → (содержимое, дописать ли)."""
    lines = article.read_text(encoding="utf-8").splitlines()
    inside_section = False
    in_block = False
    block: list[str] = []
    above = ""
    files: dict[str, tuple[str, bool]] = {}
    for line in lines:
        if not in_block and line.strip() and not FENCE.match(line):
            above = line.strip()
        if not in_block and FULL_EXAMPLE.match(line):
            inside_section = True
            continue
        if inside_section and not in_block and NEXT_SECTION.match(line):
            break
        if not inside_section:
            continue
        if FENCE.match(line):
            if in_block:
                if block:
                    found = file_of(block, above)
                    if found:
                        path, text, append = found
                        if path in files:
                            sys.exit(f"{article}: файл {path} встречается дважды")
                        files[path] = (text, append)
                    else:
                        print(f"  ⚠ {article.name}: блок без строки пути пропущен: {block[0][:60]!r}")
                block = []
                in_block = False
                above = ""
            else:
                in_block = True
            continue
        if in_block:
            block.append(line)
    if not files:
        sys.exit(f"{article}: в «Пример целиком» нет ни одного файла с путём")
    return files


def build(example_dir: Path, done: set[str]) -> None:
    rel = example_dir.relative_to(EXAMPLES).as_posix()
    if rel in done:
        return
    spec = json.loads((example_dir / "example.json").read_text(encoding="utf-8"))
    target = BUILD / rel
    if target.exists():
        shutil.rmtree(target)

    base = spec.get("base")
    if base:
        build(EXAMPLES / base, done)
        shutil.copytree(BUILD / base, target, ignore=shutil.ignore_patterns("target", "checks.sh"))
        for path in spec.get("delete", []):
            victim = target / path
            if not victim.exists():
                sys.exit(f"{rel}: в base нет файла для удаления {path}")
            victim.unlink()
    else:
        target.mkdir(parents=True)

    for item in example_dir.rglob("*"):
        if item.is_file() and item.name not in ("example.json", "checks.sh"):
            dest = target / item.relative_to(example_dir)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, dest)

    article = ROOT / spec["article"]
    files = full_example_files(article)
    for path, (text, append) in files.items():
        dest = target / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        if append and dest.exists():
            text = dest.read_text(encoding="utf-8").rstrip("\n") + "\n" + text
        dest.write_text(text, encoding="utf-8", newline="\n")

    checks = example_dir / "checks.sh"
    if checks.exists():
        shutil.copy2(checks, target / "checks.sh")

    print(f"{rel}: {len(files)} файлов из {spec['article']}" + (f", поверх {base}" if base else ""))
    done.add(rel)


def main() -> None:
    """Без аргументов — все примеры; с аргументами — только названные
    (и то, на чём они стоят): python3 tools/extract_examples.py articles/06-stand"""
    if len(sys.argv) > 1:
        specs = [EXAMPLES / name / "example.json" for name in sys.argv[1:]]
        missing = [s for s in specs if not s.exists()]
        if missing:
            sys.exit("нет примера: " + ", ".join(str(s.parent.relative_to(EXAMPLES)) for s in missing))
    else:
        specs = sorted(EXAMPLES.rglob("example.json"))
    if not specs:
        sys.exit("examples/: нет ни одного example.json")
    done: set[str] = set()
    for spec in specs:
        build(spec.parent, done)


if __name__ == "__main__":
    main()
