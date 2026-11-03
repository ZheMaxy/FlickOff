# FlickOff

**Keep your Mac. Lose the flicker.**

**A flickering Touch Bar shouldn't ruin a perfectly usable MacBook.**

You're working in a dim room. The Touch Bar gets darker — and starts flashing.
A tiny strip above the keyboard keeps pulling your eyes away from the screen.
The rest of the laptop is fine, but using it has become irritating.

Then comes the frustrating part: **macOS gives you no separate manual brightness
slider for the Touch Bar itself.** Its brightness is managed automatically. The
brightness controls *on* the Touch Bar adjust the main screen, not the strip
that's flickering.

If you're looking at a repair bill for an otherwise useful Mac, here's a
software workaround to try first.

**FlickOff lets you keep the panel at a higher, fixed brightness,
or keep its display off entirely — from the menu bar.** No terminal commands
for everyday use, no administrator access, and no need to stop system services.

This app started with the author's M1 MacBook Pro: its Touch Bar flickers at low
brightness, while a higher fixed level helps. It cannot repair a failing panel,
and it will not solve every kind of flicker. It gives you a practical way to
avoid the troublesome brightness range or stop using the display while deciding
what to do about hardware service.

[По-русски](docs/README.ru.md) · [Installation](docs/INSTALL.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md) · [Contributing](CONTRIBUTING.md)

## Download

[Download the Apple silicon beta](https://github.com/ZheMaxy/FlickOff/releases/download/v1.1.0-beta.1/FlickOff-1.1.0-arm64.zip)
or [browse all releases](https://github.com/ZheMaxy/FlickOff/releases).
Unzip, move **FlickOff.app** into Applications, then open it.

This first public beta is tested on an M1 MacBook Pro with macOS 27.2. It is
ad-hoc signed and not notarized; downloaded copies may need the
[Gatekeeper steps](docs/INSTALL.md). Noncommercial use is free; commercial use
requires a [paid license](COMMERCIAL.md).

## Controls

| Control | Behaviour |
| --- | --- |
| **Manual** | Disables automatic Touch Bar brightness and applies your chosen level. Start high, then lower it until comfortable and stable. |
| **Auto** | Returns brightness control to macOS. Idle dimming is controlled separately by the checkbox. |
| **Off** | Keeps the Touch Bar display dark while the app runs. Does not disable touch input or Touch ID. |
| **Don't dim when idle** | Prevents idle dimming and idle display power-off while the Mac is awake, unlocked and open. |
| **Launch at login** | Starts the app after login to reapply saved settings. |

First launch selects **Manual, 100%**, with idle dimming prevention enabled.
**0% is the panel's minimum lit brightness, not Off.** Slider nits are estimated
from the reported panel range; the header shows reported physical output.

Settings are remembered locally. On normal quit or SIGTERM, the app restores the
brightness/auto-brightness settings it found at launch and releases Off when the
Mac is awake and unlocked. Crashes and force quits cannot guarantee restoration.

Keeping an OLED panel lit continuously can increase power use and burn-in risk.
Use the lowest stable brightness that works for you, or choose Off.

## Compatibility

| Requirement | Status |
| --- | --- |
| Apple silicon MacBook Pro with Touch Bar | Required; the bundled app is arm64 only |
| M1 13-inch, 2020 (`MacBookPro17,1`) | Hardware tests passed on macOS 27.2; see [validation](docs/TESTING.md) |
| M2 13-inch, 2022 | Candidate hardware; not verified |
| Intel MacBook Pro, or a Mac without Touch Bar | Outside the current release scope |
| macOS 13 or later | Build/deployment minimum; private API compatibility must pass at runtime |

Earlier macOS versions have not been validated on hardware. A successful build
does not establish hardware support. The app uses private Apple frameworks;
macOS updates may change them. On an incompatible system it shows a report and
disables hardware controls. Read-only checks cannot prove that writes will work
or that visible flickering will stop.

## Build and run

Install Xcode or Command Line Tools with **Swift 6.0 or later**. Sparkle 2.10.1
is pinned through Swift Package Manager; the first build downloads it. Its
licenses are preserved in [third-party notices](THIRD_PARTY_NOTICES.md).

```sh
git clone https://github.com/ZheMaxy/FlickOff.git
cd FlickOff
git config core.hooksPath .githooks
./build.sh
open build/FlickOff.app
```

`./build.sh` runs tests, builds an arm64 release app, verifies its ad-hoc signature,
checks setup guidance, and prints a read-only compatibility report. It does not
install or launch the app. A failed compatibility report is informational on a
build machine without a Touch Bar.

```sh
./build.sh test       # automated tests; no brightness/panel changes
./build.sh install    # build, replace the app in /Applications, relaunch
```

For a managed environment reporting `sandbox_apply: Operation not permitted`,
use `SWIFTPM_DISABLE_SANDBOX=1 ./build.sh` to disable SwiftPM's nested build
sandbox. Ordinary builds leave it enabled. Release builds omit debug information.

CI runs native tests on an Intel macOS runner and separately cross-compiles the
arm64 release target. Its disposable test bundle has a separate identifier;
Intel builds are blocked outside native Intel CI. Local release builds require
arm64 and native execution without Rosetta. Hardware support is unchanged.

Local builds are ad-hoc signed, not Developer ID signed or notarized. See
[installation and Gatekeeper](docs/INSTALL.md) before sharing a binary.

## In-app updates

Use **Check for Updates…** in the menu. Enable **Check for updates automatically**
if you want periodic checks; it is off by default. Sparkle downloads updates and
handles installation from inside the app. Archives and the update feed are
Ed25519 signed and verified before installation. Update checks contact GitHub;
system profiling is disabled. The private signing key is never shipped.

## Diagnostics and tests

```sh
APP=build/FlickOff.app/Contents/MacOS/FlickOff
"$APP" --self-test     # read-only compatibility report; exit 0/1
"$APP" --setup-info    # setup guidance; no login-item registration
"$APP" --diagnose      # read-only report with selected system information
```

**Diagnostics…** in the menu also offers explicit, optional hardware probes. Each
Run button temporarily changes brightness or panel state, then reapplies the
app's settings. The brightness probe includes a low level and may cause flicker.
Review reports before sharing. The app does not upload them automatically.

Ordinary tests cover settings, controller logic, sleep/lock behaviour, failure
paths, setup guidance, report redaction and localization. Live checks are opt-in:

```sh
TB_API_TESTS=1 ./build.sh test
# Quit every running copy of the app before the next command:
TB_HARDWARE_TESTS=1 ./build.sh test
```

The [built-app integration script](Tests/Integration/README.md) additionally checks
the actual app process, its timer and shutdown cleanup.

Hardware tests briefly change the Touch Bar and attempt to restore it. They do
not prove visually that flickering has stopped. See [architecture](docs/ARCHITECTURE.md)
and [release checks](docs/RELEASING.md). Current results: [validation](docs/TESTING.md).

## License

Free for noncommercial use under **PolyForm Noncommercial 1.0.0**.
**Commercial use requires a separate paid commercial license from ZheMaxy.**
See [LICENSE](LICENSE), [NOTICE](NOTICE), and [commercial licensing](COMMERCIAL.md).

The source is available for inspection and noncommercial modification. This is
not an OSI open-source license. Public source access does not grant commercial rights.
