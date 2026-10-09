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

## The certificate

RFGEN44 **reuses LP-700-App's** Developer ID Application cert, SHA-1
`A59B8647CA9706C6E8CDBB461C9801CF715132C4`. The team already has five
Developer ID Application certs, which is Apple's limit. Revoking the LP-700
cert stops both apps from signing new releases; releases already notarized
keep working.

All of the team's current certs expire on **2027-02-01**. After renewing,
re-run the wizard below with `CERT_SHA1=<new sha1>`.

## Setting the secrets

Run the wizard from this repo, in your own terminal:

```sh
scripts/setup-signing-secrets.sh
```

It walks you through exporting the cert from Keychain Access as a `.p12`. It
checks the file by importing it into a throwaway keychain, as CI does, and
asks Apple to confirm the notary credentials. Then it writes all six secrets
with `gh` and offers to delete the `.p12`.

By hand, after exporting the `.p12`:

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
