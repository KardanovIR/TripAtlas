#!/bin/bash
# Агент сборки для Claude.
#
# Claude пишет запрос в .agent/request («<id> build» или «<id> test»), агент собирает
# проект настоящим xcodebuild для симулятора и кладёт результат в .agent/:
#   status   — «<id> running|ok|failed»
#   summary  — ошибки и упавшие тесты (коротко)
#   log.txt  — полный лог
#
# Запуск: make agent — и держите окно Терминала открытым. Остановить: Ctrl+C.
set -u
cd "$(dirname "$0")/.."
DIR=.agent
mkdir -p "$DIR"
rm -f "$DIR/request"
echo "idle" > "$DIR/status"

pick_simulator() {
  xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 \
    | sed -E 's/^[[:space:]]+//; s/ \([0-9A-F-]{36}\).*//'
}

echo "🤖 Агент сборки TripAtlas запущен. Жду запросов от Claude… (Ctrl+C — остановить)"

while true; do
  if [ -f "$DIR/request" ]; then
    read -r ID ACTION < "$DIR/request" || true
    rm -f "$DIR/request"
    ID=${ID:-0}
    ACTION=${ACTION:-build}
    echo "$ID running" > "$DIR/status"
    echo "▶︎ $(date +%H:%M:%S) [$ID] $ACTION…"

    {
      if [ ! -f TripAtlas.xcodeproj/project.pbxproj ] || [ project.yml -nt TripAtlas.xcodeproj/project.pbxproj ]; then
        xcodegen generate
      fi
      if [ "$ACTION" = "test" ]; then
        SIM=$(pick_simulator)
        echo "Симулятор: $SIM"
        xcodebuild test -project TripAtlas.xcodeproj -scheme TripAtlas \
          -destination "platform=iOS Simulator,name=$SIM" \
          -derivedDataPath "$DIR/DerivedData" CODE_SIGNING_ALLOWED=NO
      else
        xcodebuild build -project TripAtlas.xcodeproj -scheme TripAtlas \
          -destination 'generic/platform=iOS Simulator' \
          -derivedDataPath "$DIR/DerivedData" CODE_SIGNING_ALLOWED=NO
      fi
    } > "$DIR/log.txt" 2>&1
    CODE=$?

    grep -E "error:|: error|Test Case .* failed|XCTAssert|\*\* (BUILD|TEST) (SUCCEEDED|FAILED)|Executed [0-9]+ test" "$DIR/log.txt" \
      | awk '!seen[$0]++' | head -300 > "$DIR/summary"

    if [ $CODE -eq 0 ]; then
      echo "$ID ok" > "$DIR/status"
      echo "✅ $(date +%H:%M:%S) [$ID] $ACTION — успешно"
    else
      echo "$ID failed $CODE" > "$DIR/status"
      echo "❌ $(date +%H:%M:%S) [$ID] $ACTION — ошибки (Claude их видит и чинит)"
    fi
  fi
  sleep 1
done
