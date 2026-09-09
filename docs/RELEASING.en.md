# Publishing on GitHub

[中文](RELEASING.md) | **English** · [README](../README.en.md)

## First upload

Create an empty GitHub repository and push the source. Workflows use `github.repository`; there is no hardcoded owner. README links are repository-relative.

For a directory that is not already a Git repository:

```bash
git init -b main
git add .
git commit -m "Initial release of DoubaoCaret"
git remote add origin git@github.com:YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

Replace the account/repository. If Git/remotes already exist, commit and push normally. Do not commit certificates, private keys, `.toolchain/`, `build/`, or `dist/`; `.gitignore` excludes these. `BUILD-REPORT.md` is local session evidence, not public project documentation.

Enable Actions and the official actions used here in Settings → Actions → General. Organization policy must permit `contents: write` for the publish job. No PAT or custom GitHub-token secret is required; the workflow uses the automatic `GITHUB_TOKEN`.

## Default release: ad-hoc test build

**Use this path if you have no Apple signing certificate.** You do not need a paid developer account or a self-signed certificate. Leave Apple signing secrets unset and leave `MACOS_SIGNING_MODE` unset (or set it to `adhoc`). If it was previously set to `developer-id-notarized`, remove the variable or change it back to `adhoc`.

Ad-hoc signing does not provide an Apple-verified developer identity or notarization. Users may need System Settings → Privacy & Security → Open Anyway for the first launch, and updates may require granting Accessibility/Input Monitoring again; see [Permissions](PERMISSIONS.en.md). Keep the installation path `/Applications/DoubaoCaret.app` and Bundle ID stable, although this does not guarantee permission retention across ad-hoc updates. Enable the optional flow below once you obtain a Developer ID certificate.

1. Set `CFBundleShortVersionString` in `Resources/Info.plist`, for example `0.1.2`, and increment the positive integer `CFBundleVersion`.
2. Add a matching `[0.1.2]` section to `CHANGELOG.md` with Chinese and English changes; do not leave release changes only under Unreleased.
3. Commit/push and wait for **macOS CI** to pass.
4. Tag that commit:

```bash
git tag -a v0.1.2 -m "DoubaoCaret 0.1.2"
git push origin v0.1.2
```

No custom secrets are needed. `MACOS_SIGNING_MODE` defaults to `adhoc`. GitHub's macOS runner compiles both architectures; it does not download or redistribute the local Linux cross-compilation SDK.

Use `v0.1.2-rc.1` for a prerelease, while the plist and changelog remain `0.1.2`. The workflow sets GitHub's prerelease flag. Malformed tags or app-version mismatches fail before compilation.

## Pipeline and assets

`release.yml` validates versions, runs logic tests, builds the universal app, checks signatures/icons/ZIP integrity/tamper rejection, optionally signs and notarizes, verifies the final app, runs an AppKit startup smoke test, and stages assets. A separate publish job checks downloaded SHA-256 hashes before creating a release.

Assets:

- `DoubaoCaret-v0.1.2-macos-universal.zip`
- `SHA256SUMS` for the ZIP and metadata
- `build-metadata.json` with version, source commit, architectures, minimum OS, signing mode and ZIP hash

Bilingual release notes come from the matching changelog section and include installation, signing status and limitations. Ad-hoc releases explicitly say they are not notarized.

## Optional Developer ID signing and notarization

Under Settings → Secrets and variables → Actions, add the repository variable:

| Variable | Value |
|---|---|
| `MACOS_SIGNING_MODE` | `developer-id-notarized` |

Add these repository secrets:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application `.p12`, including its private key |
| `MACOS_CERTIFICATE_PASSWORD` | Nonempty password used to export that `.p12` |
| `MACOS_SIGN_IDENTITY` | Full identity, e.g. `Developer ID Application: Example Name (TEAMID)` |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64-encoded App Store Connect team API `.p8` private key for notarytool |
| `APPLE_NOTARY_KEY_ID` | API Key ID |
| `APPLE_NOTARY_ISSUER_ID` | Issuer ID associated with the team API key |

This workflow uses team API keys, not individual API keys or Apple-ID passwords. The certificate must be valid with its private key; the API key needs Apple's required notarization access. Consult [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Encode files locally and paste directly into GitHub Secrets. Do not commit or post the encoded values; Base64 is not encryption. In this mode missing secrets, signing errors or notarization rejection fail the release instead of falling back to ad-hoc signing.

A temporary Keychain and credential files are cleaned on exit. Signing secrets are supplied only to the signing step, never to PR CI. The script uses Developer ID + Hardened Runtime, waits for notarization acceptance, staples and validates the ticket, runs Gatekeeper assessment, then archives the final app again.

## Retries and troubleshooting

- **Build failure:** fix the code and use a new version/tag rather than moving a published tag.
- **Temporary pre-publication failure:** rerun failed Actions jobs. An existing release causes failure; assets are never overwritten with `--clobber`. Inspect and handle any draft left by a failed first creation before retrying.
- **403 on publication:** check repository/organization Actions policy. Only the publish job requests `contents: write`.
- **Version mismatch:** correct the plist/changelog and create the appropriate tag; renaming a ZIP is insufficient.
- **Notarization rejection:** use the logged status/submission ID to retrieve Apple's details.
- **Permissions lost on update:** see [Permissions](PERMISSIONS.en.md). Stable signing improves update identity but does not grant access automatically.

Stage release files locally without publishing (use your actual repository and commit):

```bash
python3 scripts/validate-version.py v0.1.2
python3 scripts/prepare-release.py --tag v0.1.2 \
  --repository YOUR_ACCOUNT/YOUR_REPOSITORY --commit "$(git rev-parse HEAD)" --signing adhoc
```

Output goes to `dist/release/v0.1.2/`. This command does not call GitHub. Only the tag-triggered publish job creates a public release. Automated checks do not replace real Doubao, editor caret, fullscreen or CPU validation.
