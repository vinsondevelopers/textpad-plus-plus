#!/bin/sh
# Over-the-air update files for the website: dist/Textpad++-<version>.zip (the app), dist/update.xml (GUP feed with
# SHA-256 and an ECDSA P-256 signature of the zip) and, if missing, an empty dist/pluginList.json.
# Usage: make_update.sh <app> <outdir> <version> <key.pem> <dmg url> <update.xml url>
set -eu
APP="$1"; OUT="$2"; VER="$3"; KEY="$4"; DMG_URL="$5"; FEED_URL="$6"
BASE="${FEED_URL%/*}"
ZIP="$OUT/Textpad++-$VER.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(/usr/bin/shasum -a 256 "$ZIP" | cut -d' ' -f1)
SIG=$(/usr/bin/openssl dgst -sha256 -sign "$KEY" "$ZIP" | /usr/bin/base64 | tr -d '\n')
cat > "$OUT/update.xml" <<XML
<?xml version="1.0"?>
<GUP>
	<NeedToBeUpdated>yes</NeedToBeUpdated>
	<Version>$VER</Version>
	<Location>$BASE/Textpad++-$VER.zip</Location>
	<DmgLocation>$DMG_URL</DmgLocation>
	<SHA256>$SHA</SHA256>
	<Signature>$SIG</Signature>
</GUP>
XML
[ -f "$OUT/pluginList.json" ] || printf '{"plugins": []}\n' > "$OUT/pluginList.json"
echo "  FEED $OUT/update.xml -> $BASE/Textpad++-$VER.zip (signed)"
