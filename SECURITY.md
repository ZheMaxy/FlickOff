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

## Current limits

Betas are ad-hoc signed and not notarized by Apple, and the installer package has
no Developer ID signature, so macOS can't vouch for the first download. Check it
against `SHA256SUMS` from the same release:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
```
