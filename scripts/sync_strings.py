#!/usr/bin/env python3
"""Дописывает в AIEditor/Resources/Localizable.xcstrings ключи, которые нашёл компилятор.

`xcodebuild` (в отличие от сборки в Xcode) новые строки в String Catalog не добавляет.
Источник — файлы *.stringsdata, которые сборка кладёт в build/DerivedData
(`SWIFT_EMIT_LOC_STRINGS: YES` в project.yml), поэтому сначала соберите проект:

    scripts/sim.sh build            # или команда сборки из AGENTS.md
    python3 scripts/sync_strings.py           # дописать новые ключи
    python3 scripts/sync_strings.py --check   # только проверить (код выхода 1, если есть пропуски)
    python3 scripts/sync_strings.py --prune   # заодно удалить ключи, которых больше нет в коде

Новый ключ — английская фраза, она же значение по умолчанию (язык разработки — en),
поэтому запись в каталоге пустая, как её создаёт Xcode. Множественное число
(`%lld edits`) правьте в каталоге руками — вариации `plural`.
"""
import glob
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "AIEditor/Resources/Localizable.xcstrings"
PATTERN = str(ROOT / "build/DerivedData/Build/Intermediates.noindex/AIEditor.build/*/AIEditor.build/Objects-normal/*/*.stringsdata")


def extracted_keys() -> set[str]:
    files = glob.glob(PATTERN)
    if not files:
        sys.exit("Нет *.stringsdata — сначала соберите проект (scripts/sim.sh build).")
    keys = set()
    for path in files:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        for item in data.get("tables", {}).get("Localizable", []):
            keys.add(item["key"])
    return keys


def main() -> None:
    check = "--check" in sys.argv
    prune = "--prune" in sys.argv
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    keys = extracted_keys()

    missing = sorted(keys - strings.keys())
    stale = sorted(k for k in strings.keys() - keys if strings[k].get("extractionState") != "manual")

    if check:
        for key in missing:
            print(f"нет в каталоге: {key!r}")
        for key in stale:
            print(f"нет в коде: {key!r}")
        sys.exit(1 if missing else 0)

    for key in missing:
        strings[key] = {}
    if prune:
        for key in stale:
            del strings[key]
    catalog["strings"] = dict(sorted(strings.items(), key=lambda item: item[0].lower()))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n",
                       encoding="utf-8")
    print(f"добавлено: {len(missing)}, {'удалено' if prune else 'устаревших'}: {len(stale)}")


if __name__ == "__main__":
    main()
