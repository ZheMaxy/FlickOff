# Software update publishing

FlickOff embeds Sparkle 2.10.1. Users can check from the menu. Periodic checks are
on by default and can be turned off. An update found in the background shows on
the menu bar icon and in the menu; installation uses Sparkle's standard UI. System
profiling is disabled.

The production feed is:
https://raw.githubusercontent.com/ZheMaxy/FlickOff/main/appcast.xml

Both the feed and the full update archive are Ed25519 signed. Verification is
required before archive extraction. The public key is committed in Info.plist;
the private key lives in the release owner's macOS login Keychain under account
`io.github.ZheMaxy.FlickOff`. CI does not have this key and cannot sign releases.
Keep a protected backup of the key when moving machines. Never commit/export it
into the repository or place it in command arguments.

## Build, package and sign

[RELEASING.md](RELEASING.md) has the steps. CI builds an app-only ZIP for Sparkle and
a disk image with a native installer app for first installation, and attests both.
`scripts/publish.py` verifies them and has `scripts/make_release.py` sign the ZIP,
generate and sign appcast.xml, and write SHA256SUMS. It reads the private key directly
from Keychain through Sparkle's pinned signing tool. macOS may ask you to authorize
that tool's key access.

Increment CFBundleVersion on every update, because Sparkle uses this number. Keep the
app's bundle identifier and signing key stable. Byte changes to the feed require
re-signing it.

`scripts/verify_feed.swift` checks a feed and its archives with only the public key
from Info.plist, so it can run anywhere, including CI.

The ZIP used for updates contains only FlickOff.app. License and dependency
notices are embedded in the app's Resources. Extra loose files can interfere
with app translocation and update discovery.

The installer displays the license inline; **Agree and Install** starts the
system package installation through the standard administrator authorization.
It uses no Installer GUI plugins. The native installer stops matching app copies, replaces only the app in
Applications, preserves user preferences and starts it in the console user's
GUI session. It never runs FlickOff as root. If no user is logged in, launching
is deferred to a user's manual first launch. Launch at login is enabled on that
first launch; an existing opt-out survives updates.

## Reproducible local updater test

```sh
python3 Tests/Integration/update_test.py
```

This uses temporary app copies with isolated identities and a loopback server.
It checks signed feed discovery, rejection of altered feed/archive data, and
actual update installation. It does not replace the user's installed app or
run its Touch Bar controller. It uses the release signing key locally, so it is
not a hosted CI test. CI compiles the test companion without running it.

The installer leaves the app owned by root, so updating such an installation asks
for an administrator; a Homebrew installation stays with the user and doesn't. `python3 Tests/Integration/update_test.py --root-owned`
covers that path with a temporary root-owned copy. A person has to answer its
administrator prompts.

Apple Developer ID signing/notarization is separate from Sparkle signing. The
initial beta uses an ad-hoc app signature plus Sparkle Ed25519 update signatures.
The first downloaded installer may therefore need a manual macOS exception;
link the [first-launch instructions](INSTALL.md#first-launch-if-macos-blocks-the-app)
beside the download in every release description. An updater signature does
not establish Apple notarization or remove the first-launch requirement.
