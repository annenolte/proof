#!/bin/bash
# Build proof and install it on a connected iPhone using free personal signing.
#
# TEAM is your Apple Development team. Override with PROOF_TEAM if you have several.
#
# It is read from the team Xcode last selected, NOT from the keychain identity.
# That ordering is load-bearing: signing certificates outlive the account that
# issued them, so after you sign out of one Apple ID and into another the
# keychain still offers the old team and the build fails with "No Account for
# Team X" while Xcode itself is perfectly happy. The keychain is kept only as a
# fallback for a machine that has a certificate but has never opened Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

DD="${PROOF_DD_DEVICE:-/private/tmp/proof-dd-device}"
TEAM="${PROOF_TEAM:-$(defaults read com.apple.dt.Xcode \
  IDEProvisioningTeamManagerLastSelectedTeamID 2>/dev/null || true)}"
if [ -z "$TEAM" ]; then
  TEAM="$(security find-identity -v -p codesigning \
    | sed -n 's/.*Apple Development:.*(\([A-Z0-9]*\))".*/\1/p' | head -1)"
fi

if [ -z "$TEAM" ]; then
  echo "No development team found. Open Xcode > Settings > Accounts and add your Apple ID." >&2
  exit 1
fi

# Device names contain spaces, so parse the JSON rather than the columns.
# devicectl only writes valid JSON to a real file, not to /dev/stdout.
DEVJSON="$(mktemp -t proof-devices)"
xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 || true
DEVICE="${PROOF_DEVICE_ID:-$(python3 -c "
import json,sys
try: d=json.load(open('$DEVJSON'))
except Exception: sys.exit()
for x in d.get('result',{}).get('devices',[]):
    if x.get('connectionProperties',{}).get('tunnelState') != 'unavailable':
        print(x['identifier']); break
")}"
rm -f "$DEVJSON"

echo "Team $TEAM · device ${DEVICE:-<generic>}"
xcodegen generate --quiet

xcodebuild -project proof.xcodeproj -scheme proof -configuration Debug \
  -destination "generic/platform=iOS" -derivedDataPath "$DD" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\*" || true

APP="$DD/Build/Products/Debug-iphoneos/proof.app"
[ -d "$APP" ] || { echo "No app built at $APP" >&2; exit 1; }

if [ -n "$DEVICE" ]; then
  xcrun devicectl device install app --device "$DEVICE" "$APP"
else
  echo "Built at $APP — no paired device found to install onto."
fi
