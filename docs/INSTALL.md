# Install FlickOff — Touch Bar brightness control for macOS

FlickOff requires an Apple silicon MacBook Pro with a Touch Bar and macOS 13
or later. The M1 13-inch model has been tested on macOS 27.2;
see the [compatibility table](../README.md) for current evidence.

## Install FlickOff

1. [Download FlickOff-1.1.0-arm64.dmg](https://github.com/ZheMaxy/FlickOff/releases/download/v1.1.0-beta.2/FlickOff-1.1.0-arm64.dmg).
2. Open the disk image and double-click **Install FlickOff**. If macOS blocks
   it, follow the [first-launch steps below](#first-launch-if-macos-blocks-the-app).
   Then review the license in the installer window, click **Agree and Install**,
   and confirm the macOS administrator prompt.
3. When installation finishes, FlickOff opens automatically. Find its icon
   in the **menu bar**; it does not appear in the Dock.

The installer puts the app in `/Applications/FlickOff.app`. If an existing FlickOff
is running, the installer closes it safely, replaces the app and starts the
installed copy. Your brightness settings and preferences are kept.

If the icon is not visible, press **Command–Space**, type **FlickOff**, and press
Return. If FlickOff is already running, this opens its controls in a window. The
app itself does not need administrator access to control brightness.

You do not need an Apple Developer account or subscription. The installer asks
for your Mac's administrator authorization, not an Apple Developer login.

## Install with Homebrew

```sh
brew tap zhemaxy/flickoff https://github.com/ZheMaxy/FlickOff
brew install --cask zhemaxy/flickoff/flickoff
```

FlickOff isn't notarized, because that takes a paid Apple membership. Installing
from this tap is your decision to trust this project, so the cask removes macOS's
quarantine flag and the app opens without the first-launch steps below. Homebrew
itself doesn't vouch for it: its own catalogue only takes notarized apps.

The app stays yours rather than the system's, so neither this nor later updates ask
for an administrator's password. FlickOff keeps updating itself with signed updates
as usual, not through `brew upgrade`.

Use either this or the installer. Homebrew refuses to replace a copy the installer
put in Applications, so uninstall that one first. To remove the app, run
`brew uninstall --cask flickoff`; `--zap` also deletes its settings.

## First use and launch at login

The first launch enables **Launch at login** and **Check for updates automatically**,
selects **Manual, 100%**, and sets **When idle** to **Turn off after 5 min**.
Lower the brightness to a comfortable stable
level, or choose **Off** to keep the Touch Bar display dark.
0% is minimum lit brightness, not Off. Touch ID remains available.

macOS may ask you to approve the login item in **System Settings → General →
Login Items**. The app shows guidance if approval is needed. You can turn
**Launch at login** off in the app; updates preserve that choice.

## Updating an existing installation

Use **Check for Updates…** in FlickOff. **Check for updates automatically** is
enabled by default and can be turned off. An update found in the background
shows on the menu bar icon and at the bottom of the menu. Sparkle handles the
update and verifies its signatures. The installer leaves the app owned by the
system, so macOS asks for an administrator's password to replace it.

You can also run a newer installer over the existing installation. It preserves
preferences and handles closing and reopening the app. An older installer
refuses to replace a newer build.

## First launch if macOS blocks the app

This public beta is not notarized. The installer app and FlickOff use ad-hoc
signatures rather than Developer ID signatures. macOS may say that the developer
cannot be verified or that Apple cannot check the app for malicious software.

If you trust the download from this project's GitHub Release:

1. Try opening **Install FlickOff** once so macOS records the blocked launch.
2. Open **System Settings → Privacy & Security**.
3. Find the message about **Install FlickOff** in the Security section and choose
   **Open Anyway**. On macOS versions that show **Security → Open**, open that
   section first, then choose **Open Anyway**.
4. Confirm **Open** and enter your Mac login password if macOS asks.
5. Return to the installer and choose **Agree and Install**.

If **FlickOff** itself is blocked after installation, try opening it from
Applications or Spotlight and repeat the steps for **FlickOff**. Each app has
its own exception. If Open Anyway is missing, try opening that app again and
return to Privacy & Security; the option is available for a limited time after
the attempt. A managed Mac may require your administrator's approval.

These steps apply to an unverified developer or missing notarization warning.
See [Apple's first-launch instructions](https://support.apple.com/en-gb/102445).
The Ed25519 signatures used by FlickOff's updater authenticate update downloads;
they are separate from Apple Developer ID signing and notarization.

## Build and install from source

For development, install Xcode or Command Line Tools with Swift 6.0+, then run:

```sh
./build.sh
python3 scripts/make_installer.py --output build/local-installer
```

Open the generated disk image and **Install FlickOff**. The build does not install it.
`./build.sh test` runs the ordinary automated suite without changing the panel.

## Check a download

Starting with 1.2.0, CI builds the release files and records where they came from.
With the [GitHub CLI](https://cli.github.com) you can check that a file was built by
this repository, and from which commit:

```sh
gh attestation verify FlickOff-1.2.0-arm64.dmg --repo ZheMaxy/FlickOff
```

`SHA256SUMS` in each release lists the checksums. Neither replaces notarization, but
they don't depend on a paid Apple membership.

## Quit or uninstall

**Quit** restores the brightness settings found at application startup. To remove
FlickOff, turn off **Launch at login**, choose **Quit**, and move the app from
Applications to Trash. The installer leaves the app owned by the system, so
Finder asks for an administrator's password. Saved preferences and macOS's record
of the installation are kept unless you explicitly remove them after quitting:

```sh
defaults delete io.github.ZheMaxy.FlickOff
sudo pkgutil --forget io.github.ZheMaxy.FlickOff.pkg
```

For flickering, Off mode or crash recovery, see
[Touch Bar troubleshooting](TROUBLESHOOTING.md).
