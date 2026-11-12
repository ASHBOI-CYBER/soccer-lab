#!/bin/zsh
# Build the native app for a simulator and open it on a screen:  ./sim.sh [route] [simulator-udid]
#   ./sim.sh drill:toe-taps     ./sim.sh tab:plan     ./sim.sh ob:welcome      (routes: App.swift DebugRoute)
# Console (incl. [Stage] 3D errors) ? build/console.log
set -euo pipefail
cd "$(dirname "$0")"
ROUTE=${1:-}
SIM=${2:-$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}')}
xcodebuild -project SoccerMax.xcodeproj -scheme SoccerMax -destination "id=$SIM" -derivedDataPath build build -quiet 2>&1 | grep -E "error|BUILD FAILED" && exit 1
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/SoccerMax.app
pkill -f "simctl launch --console-pty $SIM" 2>/dev/null || true
if [ -n "$ROUTE" ]; then ARGS=(-route "$ROUTE"); else ARGS=(-route ""); fi
nohup xcrun simctl launch --console-pty "$SIM" com.jacksteiner.soccermax --terminate-running-process "${ARGS[@]}" > build/console.log 2>&1 &
sleep 4
echo "launched ${ROUTE:-home}"
