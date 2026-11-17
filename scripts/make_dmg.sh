#!/bin/sh
# Build dist/Textpad++-<version>.dmg from an already-built (ad-hoc signed) Textpad++.app.
# Usage: scripts/make_dmg.sh <path/to/Textpad++.app> <outdir> <version>
set -eu
APP="$1"; OUT="$2"; VER="$3"
STAGE="$OUT/dmg-root"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp README.md "$STAGE/README.txt" 2>/dev/null || true
rm -f "$OUT/Textpad++.dmg"
hdiutil create -volname "Textpad++ $VER" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Textpad++.dmg" >/dev/null
rm -rf "$STAGE"
echo "  DMG  $OUT/Textpad++.dmg"
