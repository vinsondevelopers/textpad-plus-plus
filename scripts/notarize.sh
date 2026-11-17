#!/bin/sh
# Textpad++ — sign with Developer ID, notarize and staple the universal DMG for website download.
#
# Needs (one-time, from an Apple Developer Program account):
#   1. A "Developer ID Application" certificate in the login keychain
#        security find-identity -v -p codesigning     # must list it
#   2. A notarytool keychain profile (app-specific password from appleid.apple.com)
#        xcrun notarytool store-credentials TextpadNotary --apple-id <id> --team-id <TEAMID>
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=TextpadNotary scripts/notarize.sh [app] [outdir] [version]
#   make notarize DEVELOPER_ID=... NOTARY_PROFILE=...
#
# The app must already be built universal (`make release`). This script re-signs it with the hardened
# runtime (the Makefile's ad-hoc signature is not accepted by notarization), builds the DMG, signs it,
# submits it, waits for Apple's verdict, staples the ticket and checks it with Gatekeeper.
set -eu

APP="${1:-build/Textpad++.app}"
OUT="${2:-dist}"
VER="${3:-1.0.0}"
DMG="$OUT/Textpad++.dmg"

fail() { echo "notarize: $*" >&2; exit 2; }

[ -d "$APP" ] || fail "$APP not found; run 'make release' first"
[ -n "${DEVELOPER_ID:-}" ] || fail "set DEVELOPER_ID to your 'Developer ID Application: Name (TEAMID)' identity"
[ -n "${NOTARY_PROFILE:-}" ] || fail "set NOTARY_PROFILE to a profile created with 'xcrun notarytool store-credentials'"
security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID" >/dev/null \
  || fail "identity '$DEVELOPER_ID' is not in the keychain (security find-identity -v -p codesigning)"

ARCHS_FOUND="$(lipo -archs "$APP/Contents/MacOS/Textpad++")"
case "$ARCHS_FOUND" in
  *x86_64*arm64*|*arm64*x86_64*) ;;
  *) fail "binary is '$ARCHS_FOUND', not universal; run 'make release'" ;;
esac

echo "==> Signing $APP (hardened runtime, secure timestamp)"
codesign --force --options runtime --timestamp --entitlements resources/Textpad++.entitlements --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Building $DMG"
scripts/make_dmg.sh "$APP" "$OUT" "$VER"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

echo "==> Submitting to Apple notary service (this waits for the result)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Gatekeeper check"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
shasum -a 256 "$DMG"
echo "Ready to upload: $DMG"
