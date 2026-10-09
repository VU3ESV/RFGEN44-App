#!/usr/bin/env bash
# Builds a universal release binary, wraps it into RFGEN44.app with the
# Info.plist template, embeds AppIcon.icns, bundles the rfgen44 CLI, and
# ad-hoc signs.
# Output: dist/RFGEN44.app (CLI at RFGEN44.app/Contents/Helpers/rfgen44)
#
# Usage: VERSION=1.0.0 scripts/build-app.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/RFGEN44.app"
VERSION="${VERSION:-0.0.0-dev}"

mkdir -p "$DIST"
cd "$ROOT"

echo "==> Building universal release binaries (arm64 + x86_64) — version $VERSION"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
BIN="$BIN_PATH/RFGEN44App"
CLI="$BIN_PATH/rfgen44"
test -x "$BIN" || { echo "Binary not found at $BIN" >&2; exit 1; }
test -x "$CLI" || { echo "CLI not found at $CLI" >&2; exit 1; }

echo "==> Assembling .app bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"

cp "$BIN" "$APP/Contents/MacOS/RFGEN44App"
cp "$CLI" "$APP/Contents/Helpers/rfgen44"
chmod +x "$APP/Contents/MacOS/RFGEN44App" "$APP/Contents/Helpers/rfgen44"
cp "$CLI" "$DIST/rfgen44"

# Info.plist with version substitution.
sed "s/__VERSION__/${VERSION}/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Icon (best-effort — falls back to no icon if generation fails).
if [ ! -f "$DIST/AppIcon.icns" ]; then
    "$ROOT/scripts/make-icon.sh" || echo "==> WARNING: AppIcon.icns generation failed, shipping without icon"
fi
if [ -f "$DIST/AppIcon.icns" ]; then
    cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP/Contents/Helpers/rfgen44"
codesign --force --sign - "$DIST/rfgen44"
codesign --force --deep --sign - "$APP"

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
file "$APP/Contents/MacOS/RFGEN44App" | sed 's/^/    /'

echo "==> Built $APP"
echo "==> CLI also at $DIST/rfgen44"
