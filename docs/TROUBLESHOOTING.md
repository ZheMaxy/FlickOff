# Touch Bar flickering, brightness and Off mode troubleshooting

Use this guide if your MacBook Pro Touch Bar keeps flashing, ignores a brightness
change, or wakes after you turn its display off. For everyday controls, see
[FlickOff's brightness and Off mode guide](../README.md); for first launch, see
[installing FlickOff on macOS](INSTALL.md).

## macOS cannot verify the developer or check the app

The current beta is locally signed and has not been notarized by Apple. Try
opening the app, then use **System Settings → Privacy & Security → Open Anyway**
and confirm **Open**. Some macOS versions put this under **Security → Open**.
Follow the [complete first-launch instructions](INSTALL.md#first-launch-if-macos-blocks-the-app)
for **Install FlickOff**, and for **FlickOff** itself if it is also blocked.
You do not need an Apple Developer subscription to install or use the app.

## Touch Bar still flickers at low brightness

Choose Manual and raise brightness. If idle dimming brings flicker back, set
**When idle** to turn off or stay lit instead of letting macOS dim it. If no
comfortable level helps, try Off.
If the display still flashes in Off, the app may not control it successfully or
the fault may need hardware service.

The workaround comes from observed low-brightness flicker on one M1 MacBook Pro.
It does not diagnose the physical cause. Avoid repeated low-brightness probes if
the flashing is uncomfortable.

## Touch Bar turns back on after selecting Off

macOS or another app can wake the panel. Callbacks and a 0.5-second timer turn it
back off. Off is a software-enforced display state, not an electrical disconnect;
short wake flashes may still occur. Touch input remains active. Check that
another Touch Bar utility is not fighting the setting.

## Touch Bar goes dark when I stop using the Mac

That is **When idle** set to turn off, the default on a new installation. Using
the keyboard, trackpad or mouse lights the panel again within a moment. Choose a
longer delay, or **Stay lit**, if you would rather keep it on; staying lit speeds
up OLED burn-in.

## Unsupported system or refused brightness changes

The release is arm64-only and requires a physical Touch Bar. It dynamically
loads CoreBrightness/DFRBrightness and checks their interfaces and selected
properties. An OS update can break these private contracts. Granting
Accessibility or Full Disk Access cannot fix a missing private selector.

Right after login the system services may not be up yet. FlickOff keeps trying
for about a minute and again after waking or unlocking, so a problem shown at
that moment can clear by itself.

The menu shows a warning if macOS rejects a brightness write or keeps refusing to
turn the panel on or off. Quit other brightness utilities, reopen this app, and
inspect **Diagnostics… → Show report**, or run:

```sh
/Applications/FlickOff.app/Contents/MacOS/FlickOff --diagnose
```

This command changes no settings. The menu's optional Run buttons do briefly
change the panel and can trigger low-brightness flicker. They are disabled on an
incompatible system. API success does not prove a visible change: the probes ask
what you saw.

## Recovery after a crash or force quit

Normal quit or SIGTERM restores the brightness settings found at startup.
SIGKILL, crashes and power loss cannot run cleanup. Reopen the app, choose Auto,
and quit normally. Restart the Mac if it does not recover. Saved in-app mode is
applied again on the next launch.

## Login startup

Move the app into Applications, launch that copy, and enable **Launch at login**.
Check macOS Login Items for pending approval. Copies in Downloads or disk images
do not register automatically. Retry the toggle after correcting the installation.
If macOS refuses the automatic registration, FlickOff tries again at its next launch.

## Reporting problems and privacy

Open an issue with the app version and build from the top of the menu, Mac model,
OS version, mode and whether higher brightness or Off helped. Review diagnostic
reports before attaching them. Do not include serial numbers, credentials or
unrelated system logs.

Reports collect the app's mode, level and idle setting, model/chip/OS, selected
numeric backlight properties, private API method signatures and selected
brightness values. They exclude the broad
`StatusInfo` dump and arbitrary registry properties. UUIDs are replaced with
consistent labels. Nothing uploads automatically: Copy and Save stay local.


## “App Update Required” or a Rosetta warning

Install the current Apple silicon build. The release executable must report
`arm64` with `lipo -archs`; it does not need Rosetta. Current releases explicitly
require native execution and verify the architecture during packaging.

This warning can be triggered by an older Intel test build with the same app
identity. Check the installed binary rather than assuming the current release
uses an Intel component. Do not disable system compatibility warnings or remove
Rosetta from the system to work around an incorrectly built app.
