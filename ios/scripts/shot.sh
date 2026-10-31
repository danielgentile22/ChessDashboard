#!/bin/bash
# Screenshot one screen of the Debug app on a simulator, served from the
# recorded fixtures (openapi/fixtures), so no server or sign-in is needed.
#
#   ios/scripts/shot.sh <screen> [out.png] [game-id]   (or: make ios-shot SCREEN=games)
#   ios/scripts/shot.sh --list                         the screens it can open
#
# Builds the Debug app, boots the simulator (SIM_NAME, default "iPhone 17"),
# installs, launches with the DebugLaunch arguments (ChessDashboard/App/
# DebugLaunch.swift), waits SHOT_WAIT seconds (default 4) and saves the PNG.
# `game` opens a Game's detail (default chap0001, a fixture Game).
set -euo pipefail

SCREENS="overview trends games lessons opponents more openings events analysis game"
ios=$(cd "$(dirname "$0")/.." && pwd)

if [ "${1:-}" = --list ]; then
  printf '%s\n' $SCREENS
  exit 0
fi
screen=${1:-}
case " $SCREENS " in
  (*" $screen "*) [ -n "$screen" ] ;;
  (*) false ;;
esac || { echo "usage: shot.sh <$(echo $SCREENS | tr ' ' '|')> [out.png] [game-id]" >&2; exit 64; }
out=${2:-$ios/build/shot-$screen.png}
game=${3:-}
sim_name=${SIM_NAME:-iPhone 17}

udid=$(xcrun simctl list devices available --json | SIM_NAME="$sim_name" python3 -c '
import json, os, sys
devices = json.load(sys.stdin)["devices"]
ios = sorted((r for r in devices if "iOS" in r), reverse=True)
print(next((d["udid"] for r in ios for d in devices[r] if d["name"] == os.environ["SIM_NAME"]), ""))')
[ -n "$udid" ] || { echo "no available simulator named '$sim_name' (xcrun simctl list devices available)" >&2; exit 1; }

echo "building the Debug app for $sim_name..." >&2
(cd "$ios" && xcodegen generate --quiet)
log="$ios/build/shot-build.log"
mkdir -p "$ios/build"
xcodebuild build -project "$ios/ChessDashboard.xcodeproj" -scheme ChessDashboard \
  -derivedDataPath "$ios/build/DerivedData" -destination "id=$udid" > "$log" 2>&1 \
  || { grep -E 'error:' "$log" | sort -u | head -20; echo "build failed, full log: $log" >&2; exit 1; }
app="$ios/build/DerivedData/Build/Products/Debug-iphonesimulator/ChessDashboard.app"

xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl install "$udid" "$app"
args=(-CDFixtures -CDGuest -CDScreen "$screen")
[ -z "$game" ] || args+=(-CDGame "$game")
xcrun simctl launch --terminate-running-process "$udid" dev.danielgentile.chessdashboard "${args[@]}" > /dev/null
sleep "${SHOT_WAIT:-4}"
mkdir -p "$(dirname "$out")"
xcrun simctl io "$udid" screenshot "$out" > /dev/null 2>&1
echo "$out"
