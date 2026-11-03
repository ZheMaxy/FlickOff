# Install FlickOff — Touch Bar brightness control for macOS

FlickOff requires an Apple silicon MacBook Pro with a Touch Bar and macOS 13
or later. The M1 13-inch model has been tested on macOS 27.2;
see the [compatibility table](../README.md) for current evidence.

## Install FlickOff

1. [Download FlickOff-1.1.0-arm64.dmg](https://github.com/ZheMaxy/FlickOff/releases/download/v1.1.0-beta.2/FlickOff-1.1.0-arm64.dmg).
2. Open the disk image and double-click **Install FlickOff**. Review the license
   in that window and click **Agree and Install**. Confirm the macOS
   administrator prompt.
3. When installation finishes, FlickOff opens automatically. Find its icon
   in the **menu bar**; it does not appear in the Dock.

The installer puts the app in `/Applications/FlickOff.app`. If an existing FlickOff
is running, the installer closes it safely, replaces the app and starts the
installed copy. Your brightness settings and preferences are kept.

If the icon is not visible, press **Command–Space**, type **FlickOff**, and press
Return. The app itself does not need administrator access to control brightness.

## First use and launch at login

The first launch enables **Launch at login** and **Check for updates automatically**,
selects **Manual, 100%**, and enables **Don't dim when idle**.
Lower the brightness to a comfortable stable
level, or choose **Off** to keep the Touch Bar display dark.
0% is minimum lit brightness, not Off. Touch ID remains available.

macOS may ask you to approve the login item in **System Settings → General →
Login Items**. The app shows guidance if approval is needed. You can turn
**Launch at login** off in the app; updates preserve that choice.

## Updating an existing installation

Use **Check for Updates…** in FlickOff. **Check for updates automatically** is
enabled by default and can be turned off. Sparkle handles the update
and verifies its signatures. macOS may request permission to replace the app.

You can also run a newer installer over the existing installation. It preserves
preferences and handles closing and reopening the app. An older installer
refuses to replace a newer build.

## If macOS blocks the beta installer

This public beta is not notarized. The installer app and FlickOff use ad-hoc
signatures rather than Developer ID signatures.

After checking that the disk image came from this project's GitHub Release, try
opening **Install FlickOff**. If macOS blocks it, open **System Settings → Privacy & Security**
and use **Open Anyway** when offered, then confirm the system prompt. A managed
Mac may require your administrator's approval.

## Build and install from source

For development, install Xcode or Command Line Tools with Swift 6.0+, then run:

```sh
./build.sh
python3 scripts/make_installer.py --output build/local-installer
```

Open the generated disk image and **Install FlickOff**. The build does not install it.
`./build.sh test` runs the ordinary automated suite without changing the panel.

## Quit or uninstall

**Quit** restores the brightness settings found at application startup. To remove
FlickOff, turn off **Launch at login**, choose **Quit**, and move the app from
Applications to Trash. Saved preferences are kept unless you explicitly remove
them after quitting:

```sh
defaults delete io.github.ZheMaxy.FlickOff
```

For flickering, Off mode or crash recovery, see
[Touch Bar troubleshooting](TROUBLESHOOTING.md).
