#!/bin/bash
# Launch the demo room in a given camera mode and screenshot it.
# usage: demoshot.sh <mode: orbit|walk|plan> <outputName> [waitSeconds]
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-orbit}"
NAME="${2:-shot}"
WAIT="${3:-32}"
OUT=".recon/shots/${NAME}.png"
xcrun simctl terminate booted com.annenolte.proof >/dev/null 2>&1 || true
xcrun simctl launch booted com.annenolte.proof \
  -proofScreen demo -proofDemoPhase explore -proofDemoMode "$MODE" >/dev/null
sleep "$WAIT"
xcrun simctl io booted screenshot "$OUT" >/dev/null 2>&1
echo "$OUT"
