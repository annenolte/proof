#!/bin/bash
# Build (or test) proof for the iOS simulator.
#
# Two things here are load-bearing:
#  * DerivedData MUST live outside ~/Documents. iCloud file-provider xattrs
#    (com.apple.fileprovider.fpfs#P) make `codesign` fail with
#    "resource fork, Finder information, or similar detritus not allowed".
#  * A mutex serialises concurrent invocations. xcodegen rewrites
#    proof.xcodeproj in place, so two builds starting at once corrupt it.
set -euo pipefail
cd "$(dirname "$0")/.."

DD="${PROOF_DD:-/private/tmp/proof-dd}"
SIM="${PROOF_SIM:-iPhone 17 Pro}"
LOCK="/private/tmp/proof-build.lock"
ACTION="${1:-build}"

acquire() {
  local waited=0
  until mkdir "$LOCK" 2>/dev/null; do
    if [ -f "$LOCK/pid" ] && ! kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then
      rm -rf "$LOCK"; continue          # stale lock from a killed build
    fi
    sleep 2; waited=$((waited + 2))
    if [ "$waited" -gt 1200 ]; then
      echo "build lock held for 20 minutes, breaking it" >&2
      rm -rf "$LOCK"
    fi
  done
  echo $$ > "$LOCK/pid"
}
acquire
trap 'rm -rf "$LOCK"' EXIT

xcodegen generate --quiet
xcodebuild -project proof.xcodeproj -scheme proof \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DD" "$ACTION" 2>&1 | \
  grep -E "error:|warning: .*(deprecated|unused)|Test Case.*(passed|failed)|Executed .* tests|\*\*" || true

exit "${PIPESTATUS[0]:-0}"
