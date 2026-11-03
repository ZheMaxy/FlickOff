# Architecture

| Path | Responsibility |
| --- | --- |
| `Sources/TBPrivate` | ARC-managed Objective-C bridge to private frameworks and selected diagnostics |
| `Sources/TouchBarKit` | Main-actor controller, settings, system adapters, compatibility reports and probes |
| `Sources/FlickOff` | SwiftUI menu, AppKit controls and diagnostic windows, and CLI diagnostics |
| `Resources` | App metadata and English strings; translations go in `<lang>.lproj` |
| `Tests/TouchBarKitTests` | Fakes, regression tests and opt-in live API/hardware checks |
| `Packaging/Installer` | Native AppKit installer, inline license and package lifecycle scripts |

The controller applies settings at startup and wake, checks panel state every
0.5 seconds and reapplies brightness every 5 seconds if it has drifted. Mutable
controller state and hardware probes run on the main actor; `TouchBarKit` and its
tests compile in Swift 6 mode, so the compiler enforces this. Timers and observers
are removed on shutdown and deinitialization.

The panel callback comes from `DFRBrightnessClient`; on/off state is read through
corebrightnessd. Leaving Off and quitting never explicitly light the panel while
the system sleeps, the lid is closed, the built-in display sleeps or the screen
is locked.

Polling must stay invisible. `@Published` notifies even when a value is unchanged,
and every notification redraws the menu bar icon, so the controller publishes only
real changes. The light output lives in `PanelTelemetry` and is read only while a
window is open. The login item status is polled only while approval is pending.
The timer allows coalescing and stops during sleep.

`IdleBehavior` decides what happens without input: leave it to macOS, undo dimming
and power-off, or do that until a delay passes and then turn the panel off. Idle
time is the shorter of the time since the last input and the time since the last
activity the app noticed itself: launch, wake, unlock, a setting change, or the
panel being lit by someone else. corebrightnessd reports a state change a moment
late, so "on" only counts as someone lighting the panel once "off" has been seen.

### When things go wrong

A failed launch check is retried for about a minute and on wake or unlock if a
service may just not be up yet; a missing Touch Bar or a changed private API is
not. Brightness reads are optional: no answer never becomes "manual, 0%", and
nothing is written until the launch-time brightness is known, because it is what
quitting restores. Refused on/off/undim calls raise a warning after several in a
row. A probe registers a recovery step that runs if the app quits before it ends,
and lights a dark panel first so that "no visible change" stays meaningful. While
another user owns the console the app hands back brightness and Off and writes
nothing. A second copy exits before touching anything and asks the running one to
show its controls.

## Private interfaces

`TBPrivateAPI.h` declares the private classes for the whole target, and
`TBTouchBar.m` lists the selectors the app can't work without in `RequiredAPIs()`.
Dynamic framework loads are cached. Compatibility checks read the device-tree marker, private interfaces,
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
not start update checks. It implements Sparkle's gentle reminders: without a Dock
icon an alert could open unnoticed behind other windows, so a scheduled update
shows on the menu bar icon and in the menu until the user looks at it.

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
opening FlickOff. It skips launching when nobody is logged in. The installed app
stays owned by root, which protects it from processes of the user, so Sparkle
asks for an administrator to replace it.

The app enables launch at login on first launch from Applications and defaults
automatic update checks to on. Existing opt-outs are preserved. In-app updates
use the signed app-only ZIP rather than the installer disk image.
