# Releasing Clipy

This document covers the maintainer-facing release setup that the public `README` no longer needs to carry inline.

## Release Modes

Clipy supports two distribution modes:

- Developer ID-signed and notarized releases with Sparkle appcasts and in-app updates
- Unsigned manual-download releases with a GitHub Releases fallback in Preferences

## Release Infrastructure

The release pipeline uses Sparkle with GitHub-hosted artifacts:

- `docs/appcast.xml` is published via GitHub Pages at `https://goniszewski.github.io/Clipy/appcast.xml` when `SPARKLE_PRIVATE_KEY` is configured
- Sparkle `.zip` update archives are uploaded to GitHub Releases
- `.dmg` archives are uploaded to GitHub Releases for manual installs
- Full trust on other Macs requires Developer ID signing and notarization

## Required Secrets

- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_ID_APP_PASSWORD`
- `SPARKLE_PRIVATE_KEY`

`SPARKLE_PRIVATE_KEY` is the private EdDSA key exported from Sparkle's `generate_keys` tool. The public key is embedded in `Info.plist` as `SUPublicEDKey`.

## One-Time GitHub Setup

1. Enable GitHub Pages for this repository with source `main` and folder `/docs`.
2. Bootstrap the Sparkle keypair, update `SUPublicEDKey`, and store the private key as a GitHub secret:

```bash
./scripts/bootstrap-sparkle-key.sh
```

This uses a repo-specific Sparkle keychain account by default and updates `SPARKLE_PRIVATE_KEY` on the current GitHub repo.

3. If you prefer the manual flow, export the Sparkle private key from your login keychain:

```bash
./Pods/Sparkle/bin/generate_keys -x /tmp/clipy-sparkle-private-key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/clipy-sparkle-private-key
rm /tmp/clipy-sparkle-private-key
```

4. Add the Apple signing and notarization secrets listed above.

## Workflow Behavior

If the Apple signing secrets are not configured yet, the Release workflow falls back to publishing unsigned, unnotarized artifacts as manual-download releases only. Users can still install them by following the Gatekeeper bypass steps in the main `README`, but Sparkle appcasts are skipped because unsigned builds cannot be validated as automatic updates.

If `SPARKLE_PRIVATE_KEY` is missing or empty, the Release workflow skips appcast generation and publishes a manual-download release only.
