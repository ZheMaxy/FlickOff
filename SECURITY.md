# Security policy

FlickOff installs through an administrator-approved package and updates itself, so
problems in those paths matter most.

## Reporting a vulnerability

Please report it privately through
[Report a vulnerability](https://github.com/ZheMaxy/FlickOff/security/advisories/new),
not in a public issue. Include the version and build from the top of the menu, your
macOS version and the steps to reproduce it. This is a one-person project, so
reports are handled on a best-effort basis.

Only the latest release gets fixes.

## What protects you today

- Update feeds and archives are Ed25519 signed, and Sparkle verifies them before
  extracting anything. The private key stays in the owner's Keychain and never
  enters this repository or CI.
- The app itself runs as your user and is never started as root. Only the
  installer's package scripts run as root, after you approve the administrator
  prompt.

- Starting with 1.2.0, CI builds the release files and attests them, and the feed
  is checked daily with only the public key.

## Current limits

Betas are ad-hoc signed and not notarized by Apple, which takes a paid membership, and
the installer package has no Developer ID signature, so macOS can't vouch for the first
download. You can check it yourself:

```sh
gh attestation verify FlickOff-1.2.0-arm64.dmg --repo ZheMaxy/FlickOff
shasum -a 256 -c SHA256SUMS --ignore-missing
```

The Homebrew cask removes macOS's quarantine flag because of this, so Gatekeeper
doesn't check that copy at all. Installing from this tap means trusting this project.
