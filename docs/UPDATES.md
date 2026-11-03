# Software update publishing

FlickOff embeds Sparkle 2.10.1. Users can check from the menu or opt into periodic
checks. Automatic checking is enabled by default; installation uses Sparkle's
standard UI. System profiling is disabled.

The production feed is:
https://raw.githubusercontent.com/ZheMaxy/FlickOff/main/appcast.xml

Both the feed and the full update archive are Ed25519 signed. Verification is
required before archive extraction. The public key is committed in Info.plist;
the private key lives in the release owner's macOS login Keychain under account
`io.github.ZheMaxy.FlickOff`. CI does not have this key and cannot sign releases.
Keep a protected backup of the key when moving machines. Never commit/export it
into the repository or place it in command arguments.

## Build, package and sign

1. Increment CFBundleVersion on every update; Sparkle uses this number. Set the
   human-readable CFBundleShortVersionString and check platform requirements.
2. Run `./build.sh`, the live hardware suite and integration checks appropriate
   to the change. Keep the app's bundle identifier and signing key stable.
3. Create a fresh output directory and run:

```sh
python3 scripts/make_release.py --tag v1.1.0-beta.2 --output build/release-1.1.0-beta.2
```

The script makes an app-only ZIP for Sparkle and a disk image with a native
installer app for first installation. The installer embeds a system package.
The script preserves framework symlinks, signs the ZIP, generates and
signs appcast.xml, verifies both signatures, and writes SHA256SUMS for the ZIP
and installer. It reads the private key directly from Keychain through Sparkle's
pinned signing tool. macOS may ask you to authorize that tool's key access.

4. Validate the package and image with `Tests/Integration/installer_test.py` as
   described in the integration README. Upload the DMG, ZIP and SHA256SUMS
   to the matching GitHub Release. Verify the asset
   URL is available, then copy the generated appcast.xml unchanged to the repo
   root and publish it. Byte changes to the feed require re-signing it.
5. Download the published archive/feed and verify their signatures and checksum.
   Check a prior app version discovers the update and the current build reports
   no newer version.

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

Apple Developer ID signing/notarization is separate from Sparkle signing. The
initial beta uses an ad-hoc app signature plus Sparkle Ed25519 update signatures.
