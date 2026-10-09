#!/usr/bin/env bash
# Builds RFGEN44.app, signs it (and the bundled rfgen44 CLI) with Developer ID +
# hardened runtime, notarizes and staples the app, then builds, signs, notarizes
# and staples the DMG. Used by .github/workflows/release.yml; also runnable locally.
#
# Signing is GATED on secrets — with none set it keeps build-app.sh's ad-hoc
# signature, so the build still succeeds (but Gatekeeper will block the
# download on other Macs).
#
#   VERSION=0.1.0 scripts/package-signed.sh      → dist/RFGEN44-0.1.0.dmg
#
# Env — signing (CI secrets, see docs/SIGNING-SECRETS.md):
#   MACOS_CERT_P12_BASE64   base64 of a Developer ID Application .p12 (cert + key)
#   MACOS_CERT_PASSWORD     the .p12 export password
#   KEYCHAIN_PASSWORD       password for the temp keychain (any value)
# Env — notarization (optional; needs the signing cert too):
#   NOTARY_APPLE_ID         Apple ID email
#   NOTARY_TEAM_ID          team id (Y6FT52BKDA)
#   NOTARY_PASSWORD         app-specific password for that Apple ID
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
APP="dist/RFGEN44.app"
CLI="$APP/Contents/Helpers/rfgen44"
DMG="dist/RFGEN44-${VERSION}.dmg"
TMP="${RUNNER_TEMP:-$(mktemp -d)}"

echo "==> Building app (v$VERSION)"
VERSION="$VERSION" ./scripts/build-app.sh

# --- import the signing cert into a throwaway keychain ----------------------------------
IDENTITY=""
KC=""
cleanup() {
  # Deleting the keychain also drops it from the search list.
  if [ -n "$KC" ]; then security delete-keychain "$KC" 2>/dev/null || true; fi
}
trap cleanup EXIT

if [ -n "${MACOS_CERT_P12_BASE64:-}" ]; then
  echo "==> Importing Developer ID certificate into a temporary keychain"
  KC="$TMP/rfgen44-signing.keychain-db"
  KCPW="${KEYCHAIN_PASSWORD:-rfgen44-ci-temp}"
  security create-keychain -p "$KCPW" "$KC"
  security set-keychain-settings -lut 21600 "$KC"
  security unlock-keychain -p "$KCPW" "$KC"
  echo "$MACOS_CERT_P12_BASE64" | base64 --decode > "$TMP/cert.p12"
  security import "$TMP/cert.p12" -k "$KC" -P "${MACOS_CERT_PASSWORD:-}" -T /usr/bin/codesign
  rm -f "$TMP/cert.p12"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPW" "$KC" >/dev/null
  # Make the temp keychain searchable (keep the existing ones too; word-split on purpose).
  # shellcheck disable=SC2046
  security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
  # In the fresh keychain there is exactly one Developer ID identity, so name-selection is unambiguous.
  IDENTITY="$(security find-identity -v -p codesigning "$KC" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
  test -n "$IDENTITY" || { echo "No Developer ID Application identity in the .p12" >&2; exit 1; }
fi

# codesign with a few retries — Apple's secure-timestamp service is intermittently unavailable
# ("The timestamp service is not available."), which would otherwise fail the whole release.
cs() {
  local n=1
  until codesign "$@"; do
    [ "$n" -ge 4 ] && return 1
    echo "  codesign attempt $n failed — retrying in 15s…" >&2; sleep 15; n=$((n + 1))
  done
}

# --- sign inside-out (bundled CLI first, then the app) ----------------------------------
# No entitlements: the app is not sandboxed, and IOKit HID access to a vendor-defined
# device needs none under the hardened runtime.
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with: $IDENTITY"
  cs --force -s "$IDENTITY" -o runtime --timestamp -i com.vu3esv.rfgen44-cli "$CLI"
  cs --force -s "$IDENTITY" -o runtime --timestamp "$APP"
else
  echo "==> WARNING: no MACOS_CERT_P12_BASE64 — keeping the ad-hoc signature (not distributable)"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

# --- helper: submit to the notary service; fail unless Apple says "Accepted" ------------
notarize() {  # $1 = path to a .zip or .dmg to submit
  local auth=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
  local out id status
  out="$(xcrun notarytool submit "$1" "${auth[@]}" --wait --output-format json)" || true
  echo "$out"
  id="$(plutil -extract id raw -o - - <<< "$out" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - - <<< "$out" 2>/dev/null || true)"
  if [ "$status" != "Accepted" ]; then
    echo "Notarization of $1 failed (status: ${status:-unknown})" >&2
    [ -n "$id" ] && xcrun notarytool log "$id" "${auth[@]}" >&2 || true
    return 1
  fi
}
HAVE_NOTARY=0
if [ -n "$IDENTITY" ] && [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
  HAVE_NOTARY=1
fi

# Notarize the APP and staple it first, so the bundle carries its ticket even offline and
# once copied out of the DMG (not just while the DMG is mounted).
if [ "$HAVE_NOTARY" = 1 ]; then
  echo "==> Notarizing the app + stapling (a few minutes)…"
  AZIP="$TMP/RFGEN44-app.zip"
  ditto -c -k --keepParent "$APP" "$AZIP"
  notarize "$AZIP"
  rm -f "$AZIP"
  xcrun stapler staple "$APP"
  spctl -a -t exec -vv "$APP"
fi

echo "==> Building DMG"
VERSION="$VERSION" ./scripts/make-dmg.sh

# Codesign the DMG container too (so `spctl -t open` accepts it and it mounts without a
# Gatekeeper prompt), then notarize + staple the DMG itself.
if [ -n "$IDENTITY" ]; then
  echo "==> Codesigning the DMG"
  cs --force -s "$IDENTITY" --timestamp "$DMG"
fi
if [ "$HAVE_NOTARY" = 1 ]; then
  echo "==> Notarizing the DMG + stapling (a few minutes)…"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
  echo "==> Notarized + stapled (app + DMG)."
elif [ -n "$IDENTITY" ]; then
  echo "==> Skipping notarization (no NOTARY_* secrets) — signed but not notarized."
fi
echo "==> Done: $DMG"
