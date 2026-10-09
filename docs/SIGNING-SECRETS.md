# Release signing secrets (RFGEN44-App)

The release workflow ([`.github/workflows/release.yml`](../.github/workflows/release.yml))
signs `RFGEN44.app` and its bundled `rfgen44` CLI with Developer ID and the
hardened runtime, then notarizes and staples both the app and the DMG. It
runs [`scripts/package-signed.sh`](../scripts/package-signed.sh), which also
works locally.

The workflow **refuses to run** until these GitHub Actions secrets are set on
this repo (*Settings → Secrets and variables → Actions*). Run locally without
them, the script still builds the DMG but leaves it ad-hoc signed.

## Secrets

| Secret | What it is |
|--------|------------|
| `MACOS_CERT_P12_BASE64` | a **Developer ID Application** cert + private key exported as `.p12`, base64-encoded |
| `MACOS_CERT_PASSWORD` | the password set when exporting that `.p12` |
| `KEYCHAIN_PASSWORD` | any value; password for the throwaway CI keychain |
| `NOTARY_APPLE_ID` | Apple ID email used for notarization |
| `NOTARY_TEAM_ID` | the team id (`Y6FT52BKDA`) |
| `NOTARY_PASSWORD` | an **app-specific password** for that Apple ID ([appleid.apple.com](https://appleid.apple.com) → Sign-In & Security → App-Specific Passwords) |

The notary secrets can be the same values the sibling apps use. The CI
keychain holds only the one imported cert, so the script selects it by name.

## Choosing the certificate

The sibling apps each use their own Developer ID Application cert under team
`Y6FT52BKDA`, so revoking one does not affect the others. Apple allows at most
five Developer ID Application certs per team, and the dev Mac already holds
five, so either:

- export one of the existing certs for RFGEN44 too, or
- revoke an unused one in the developer portal and create a dedicated
  RFGEN44 cert.

## Exporting the `.p12` and setting the secrets

Keychain Access → **login** keychain → **My Certificates** → the chosen
`Developer ID Application` → right-click → **Export…** → `.p12`, set a
password. Then, from this repo:

```sh
base64 -i RFGEN44.p12 | gh secret set MACOS_CERT_P12_BASE64
gh secret set MACOS_CERT_PASSWORD             # prompts for the .p12 password
gh secret set KEYCHAIN_PASSWORD -b "$(uuidgen)"
gh secret set NOTARY_APPLE_ID                 # prompts
gh secret set NOTARY_TEAM_ID -b Y6FT52BKDA
gh secret set NOTARY_PASSWORD                 # prompts for the app-specific password
rm RFGEN44.p12
```

## Cutting a release

```sh
git tag v0.1.0 && git push origin v0.1.0      # or:
gh workflow run release.yml -f version=0.1.0  # tags the current main
```

The release gets `RFGEN44-<version>.dmg`, its `.sha256`, and notes that pull in
that version's [CHANGELOG](../CHANGELOG.md) section. The repo is private, so
only collaborators can download it, and each run spends macOS minutes from
the private-repo quota.

## Notarization alternative (App Store Connect API key)

Instead of Apple ID + app-specific password you may prefer an ASC API key
(no 2FA or password expiry). That means switching `notarize()` in
`package-signed.sh` to `--key/--key-id/--issuer` with `NOTARY_API_KEY` /
`NOTARY_API_KEY_ID` / `NOTARY_API_ISSUER` secrets.
