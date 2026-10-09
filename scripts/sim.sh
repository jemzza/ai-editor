#!/bin/bash
# Свой симулятор для каждой ветки/worktree — агенты, работающие параллельно,
# не мешают друг другу. Build.command не трогает: он для проверяющего.
#
#   scripts/sim.sh                     найти/создать «AIEditor-<ветка>», загрузить, напечатать UDID
#   scripts/sim.sh build               xcodegen + сборка под этот симулятор
#   scripts/sim.sh test [args…]        xcodegen + тесты на нём (args уходят в xcodebuild,
#                                      например -only-testing:AIEditorTests/EditServiceTests)
#   scripts/sim.sh run [-- args…]      сборка + установка + запуск (args — launch-аргументы,
#                                      например -- -mockData -mockSlowStream)
#   scripts/sim.sh --ios18 <команда>   то же на «AIEditor-<ветка>-ios18» (последний установленный iOS 18.x)
#
# Никогда не делает `simctl shutdown all` / `erase all`, не трогает чужие симуляторы
# и не закрывает Simulator.app. DerivedData — build/DerivedData внутри текущего worktree.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SCHEME="AIEditor"
BUNDLE_ID="com.example.aieditor.app"
DERIVED="$ROOT/build/DerivedData"

IOS18=0
if [ "${1:-}" = "--ios18" ]; then
  IOS18=1
  shift
fi
COMMAND="${1:-udid}"
[ $# -gt 0 ] && shift

# Ветка без коммитов тоже имеет имя (`symbolic-ref`); detached HEAD — короткий хеш.
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD)"
SAFE_BRANCH="$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' '-')"
NAME="AIEditor-$SAFE_BRANCH"
[ "$IOS18" = "1" ] && NAME="$NAME-ios18"

# UDID своего симулятора по имени; создаёт, если нет. Выбор runtime и модели — в python
# (JSON simctl), потому что сравнивать версии в bash ненадёжно.
find_or_create() {
  python3 - "$NAME" "$IOS18" <<'PY'
import json, re, subprocess, sys

name, ios18 = sys.argv[1], sys.argv[2] == "1"

def simctl(*args):
    return subprocess.run(["xcrun", "simctl", *args], check=True, capture_output=True, text=True).stdout

devices = json.loads(simctl("list", "devices", "-j"))["devices"]
for runtime, items in devices.items():
    for device in items:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)

runtimes = [r for r in json.loads(simctl("list", "runtimes", "-j"))["runtimes"]
            if r.get("isAvailable") and r.get("platform", "iOS") == "iOS" and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
if ios18:
    runtimes = [r for r in runtimes if r["version"].startswith("18.")]
if not runtimes:
    sys.exit("Нет подходящего iOS runtime" + (" 18.x (Xcode → Settings → Components)" if ios18 else ""))
version = lambda r: tuple(int(part) for part in r["version"].split("."))
runtime = max(runtimes, key=version)

# Самый новый iPhone, который поддерживает этот runtime: базовая модель с наибольшим номером
# («iPhone 17», не «17e» / «Pro Max»); если таких нет — с наибольшей `minRuntimeVersion`.
supported = {t["identifier"] for t in runtime.get("supportedDeviceTypes", [])}
iphones = [t for t in json.loads(simctl("list", "devicetypes", "-j"))["devicetypes"]
           if t["identifier"] in supported and t.get("productFamily") == "iPhone"]
if not iphones:
    sys.exit(f"В runtime {runtime['version']} нет iPhone")
plain = [t for t in iphones if re.fullmatch(r"iPhone \d+", t["name"])]
if plain:
    device_type = max(plain, key=lambda t: int(t["name"].split()[1]))
else:
    device_type = max(iphones, key=lambda t: (t.get("minRuntimeVersion", 0), -len(t["name"])))

udid = simctl("create", name, device_type["identifier"], runtime["identifier"]).strip()
print(f"Создан {name}: {device_type['name']}, iOS {runtime['version']}", file=sys.stderr)
print(udid)
PY
}

UDID="$(find_or_create)"

# Загрузка идемпотентна: уже загруженный — не ошибка.
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

generate() {
  xcodegen generate --quiet --spec project.yml
}

xcodebuild_on_sim() {
  xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" "$@"
}

case "$COMMAND" in
  udid)
    echo "$UDID"
    ;;
  build)
    generate
    xcodebuild_on_sim build -quiet "$@"
    echo "✅ $NAME ($UDID): сборка готова"
    ;;
  test)
    generate
    xcodebuild_on_sim test -quiet "$@"
    echo "✅ $NAME ($UDID): тесты прошли"
    ;;
  run)
    [ "${1:-}" = "--" ] && shift
    generate
    xcodebuild_on_sim build -quiet
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"
    xcrun simctl install "$UDID" "$APP"
    # Перезапуск с новыми аргументами: старый процесс приложения на ЭТОМ симуляторе закрываем.
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
    echo "✅ $NAME ($UDID): приложение запущено. Окно: open -a Simulator (не закрывайте его — им пользуются другие)."
    ;;
  *)
    echo "Неизвестная команда: $COMMAND (udid | build | test | run)" >&2
    exit 2
    ;;
esac
