#!/bin/zsh
# iPhone Duo check (2026-11-01): every main screen, one screenshot each, for the pose the simulator is in now.
#   ./duo-check.sh <sim-udid> <pose-name>      e.g. ./duo-check.sh $DUO open-portrait
# Fold / open / turn the simulator between runs (Device Hub, Xcode 27.1+). Shots ? ../../out/review/duo/<pose>/.
set -euo pipefail
cd "$(dirname "$0")"
SIM=$1; POSE=$2
OUT=../../out/review/duo/$POSE; mkdir -p $OUT
APP=build/Build/Products/Debug-iphonesimulator/SoccerMax.app
[[ -d $APP ]] || { echo "build first: xcodebuild ? -derivedDataPath build"; exit 1; }
xcrun simctl install $SIM $APP
xcrun simctl status_bar $SIM override --time 9:41 --batteryState charged --batteryLevel 100 2>/dev/null || true
for r in ob:welcome ob:name ob:paywall tab:sessions tab:matchday tab:team tab:stats tab:profile launch40 stay; do
  xcrun simctl launch --terminate-running-process $SIM com.jacksteiner.soccermax -route "$r" >/dev/null
  sleep 9
  # the Duo has 2 screens: 1 = outer (closed), 3 = inner (open) ? the one that's off comes out black
  xcrun simctl io $SIM screenshot --display=1 "$OUT/${r/:/-}-outer.png" >/dev/null 2>&1 || true
  xcrun simctl io $SIM screenshot --display=3 "$OUT/${r/:/-}-inner.png" >/dev/null 2>&1 || true
  echo "  $POSE  $r"
done
echo "shots in $OUT"
