# Install FlickOff

You need an Apple silicon MacBook Pro with a Touch Bar. The build target is
macOS 13+, but only the M1 model has been used to validate the original hardware
behaviour. The app checks private API compatibility on every launch.

## Download

Get the arm64 archive from [GitHub Releases](https://github.com/ZheMaxy/FlickOff/releases).
Expand it and move FlickOff.app into Applications before opening it. Keep only
one active copy. The archive contains the app, including its license notices.

## Build from source

Install Xcode or Command Line Tools with Swift 6.0+, then run `./build.sh` in the
repository. The result is `build/FlickOff.app`. No administrator access
is needed to build or to control brightness.

## Install

1. Quit any running copy of FlickOff.
2. Move `FlickOff.app` to `/Applications` or `~/Applications`.
3. Open it from that folder. It appears in the menu bar, without a Dock icon.
4. Select **Manual** and start with higher brightness if low levels flicker.
   Alternatively, choose **Off** to keep the display dark.

Running a downloaded app outside Applications can lead to a translocated,
temporary path, which is unsuitable for reliable launch at login.

`./build.sh install` builds, replaces the app in `/Applications` and relaunches
it. Do not use that command just to build or test.

## Gatekeeper

Local builds use an ad-hoc signature. Downloaded copies without a Developer ID
signature and notarization may be blocked by Gatekeeper.

After checking where the app came from, try opening it, then use **System Settings
→ Privacy & Security → Open Anyway** if macOS offers that option. Follow the
confirmation prompts. Managed Macs may prohibit this exception.

Do not disable Gatekeeper globally or remove quarantine from unrelated files.
If macOS says an app is damaged, rebuild it from trusted source and check the
signature instead of assuming it is safe to open.

## Launch at login

The app attempts to register itself on the first launch from Applications. macOS
may require approval under **System Settings → General → Login Items** (the pane
name varies by OS version). The app provides localized guidance and a shortcut.

The **Launch at login** toggle controls registration. Turning it off is remembered,
including if you later move the app into Applications.

## Quit, recover, uninstall

**Quit** restores the brightness settings found before the app started. The app
remembers its own selected mode for next time. Off controls the display only;
touch input can still work.

To uninstall, disable **Launch at login**, quit, then remove the app. To also
remove saved preferences, run this after quitting:

```sh
defaults delete io.github.ZheMaxy.FlickOff
```

If a crash leaves unexpected brightness or a dark panel, reopen the app, choose
Auto, and quit normally. Restart the Mac if it does not recover.
See [troubleshooting](TROUBLESHOOTING.md).
