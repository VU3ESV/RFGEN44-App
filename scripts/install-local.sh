#!/usr/bin/env bash
# Builds RFGEN44.app and installs it to /Applications on this Mac, plus the
# rfgen44 CLI to /usr/local/bin (if writable).
#
# Steps:
#   1. Run scripts/build-app.sh (universal release, ad-hoc signed).
#   2. ditto-copy the .app to /Applications, replacing any existing copy.
#   3. Strip the com.apple.quarantine xattr so Gatekeeper does not block
#      the ad-hoc-signed binary on first launch.
#
# Usage:
#   VERSION=$(git describe --tags --always) scripts/install-local.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="RFGEN44.app"
SRC_APP="$DIST/$APP_NAME"
DEST_APP="/Applications/$APP_NAME"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.0.0-dev)}"

echo "==> Building $APP_NAME (version $VERSION)"
VERSION="$VERSION" "$ROOT/scripts/build-app.sh"

test -d "$SRC_APP" || { echo "Build did not produce $SRC_APP" >&2; exit 1; }

install_app() {
    "$@" rm -rf "$DEST_APP"
    "$@" /usr/bin/ditto "$SRC_APP" "$DEST_APP"
    "$@" /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
}

ERR="$(mktemp)"
if ! install_app 2>"$ERR"; then
    if grep -qi "permission denied" "$ERR"; then
        echo "==> Permission denied without sudo, re-trying with sudo"
        install_app sudo
    else
        cat "$ERR" >&2
        exit 1
    fi
fi
rm -f "$ERR"

if [ -w /usr/local/bin ]; then
    cp "$DIST/rfgen44" /usr/local/bin/rfgen44
    echo "==> Installed CLI: /usr/local/bin/rfgen44"
else
    echo "==> CLI not installed (/usr/local/bin not writable). Use: $DEST_APP/Contents/Helpers/rfgen44"
fi

echo
echo "==> Installed: $DEST_APP"
echo "==> Launch with: open '$DEST_APP'"
