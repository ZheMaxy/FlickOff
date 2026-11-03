# Architecture

| Path | Responsibility |
| --- | --- |
| `Sources/TBPrivate` | ARC-managed Objective-C bridge to private frameworks and selected diagnostics |
| `Sources/TouchBarKit` | Main-actor controller, settings, system adapters, compatibility reports and probes |
| `Sources/FlickOff` | SwiftUI menu, AppKit diagnostic window and CLI diagnostics |
| `Resources` | App metadata and English strings; translations go in `<lang>.lproj` |
| `Tests/TouchBarKitTests` | Fakes, regression tests and opt-in live API/hardware checks |
| `Packaging/Installer` | Native AppKit installer, inline license and package lifecycle scripts |

The controller applies settings at startup and wake, checks panel state every
0.5 seconds and reapplies brightness every 5 seconds if it has drifted. Mutable
controller state and hardware probes run on the main actor. Timers and observers
are removed on shutdown and deinitialization.

The panel callback comes from `DFRBrightnessClient`; on/off state is read through
corebrightnessd. Leaving Off and quitting never explicitly light the panel while
the system sleeps, the lid is closed, the built-in display sleeps or the screen
is locked.

## Private interfaces

`TBTouchBar.m` lists selectors in `RequiredAPIs()`. Dynamic framework loads are
cached. Compatibility checks read the device-tree marker, private interfaces,
integer display addressing, selected property types/ranges and dimming step.
They do not write settings. They cannot guarantee future private API ABI
compatibility or accepted writes; brightness-write failures appear in the menu.

CoreBrightness uses integer display IDs with `copyPropertyForKey:andDisplay:`
and `setProperty:withKey:andDisplay:`. Keys include `DisplayBrightnessAuto`,
`DisplayBrightness`, `DFRDisplayState` (2 on, 1 off) and
`DisplayPanelLuminanceMin/Max`. Slider nits are estimated linearly over that range.

DFRBrightness provides `getDFRDisplayID`, `getDimmingStep`, `turnOn`, `turnOff`,
`dimToStep:`, `scheduleWithDispatchQueue:` and
`registerDisplayStateUpdateCallbackWithBlock:`. Optional probes additionally try
`dimToStep:withCoefficient:` and report missing/refused calls.

On normal quit the launch-time brightness mode/manual level are restored. Off
is released only if the panel may be lit. App preferences remain for next time.
Diagnostic reports stay local. Optional software update checks contact GitHub
through Sparkle; update installation uses its signed helper components. System
profiling is disabled.


## Software updates

`Sources/FlickOff/UpdateController.swift` owns one Sparkle standard updater.
The menu observes its KVO state, disables repeated checks while one is active,
and changes Sparkle's own automatic-check preference only in response to a user
setting. The updater starts only in the GUI app; read-only CLI diagnostics do
not start update checks.

The pinned Sparkle framework is embedded with symlinks and vendor signatures
preserved. Every Mach-O helper must contain the build architecture; the release
main executable is arm64-only. `SUVerifyUpdateBeforeExtraction` and
`SURequireSignedFeed` require authenticated archives and feed metadata.
`SUEnableSystemProfiling` is false. The owner's signing key is kept in macOS
Keychain; only its public key is in Info.plist.

## Installation

`scripts/make_installer.py` creates a disk image containing Install FlickOff.app.
The AppKit window presents the license and one Agree and Install action. Its
unprivileged process passes the embedded package path as an AppleScript argument;
the quoted path is used with the system `installer` command and administrator
authorization. No credentials are stored or put in command arguments.

The package installs only `/Applications/FlickOff.app`. Its preinstall script
rejects downgrades and conflicting identities, then sends SIGTERM to matching
app copies so settings are restored before replacement. Package upgrade metadata
replaces the app bundle and removes stale files while leaving preferences alone.
The postinstall script selects the console user's session and drops root before
opening FlickOff. It skips launching when nobody is logged in.

The app enables launch at login on first launch from Applications and defaults
automatic update checks to on. Existing opt-outs are preserved. In-app updates
use the signed app-only ZIP rather than the installer disk image.
