# Troubleshooting

## Flickering continues

Choose Manual, raise brightness, and leave **Don't dim when idle** enabled if
idle dimming brings flicker back. If no comfortable level helps, try Off.
If the display still flashes in Off, the app may not control it successfully or
the fault may need hardware service.

The workaround comes from observed low-brightness flicker on one M1 MacBook Pro.
It does not diagnose the physical cause. Avoid repeated low-brightness probes if
the flashing is uncomfortable.

## Off comes back on briefly

macOS or another app can wake the panel. Callbacks and a 0.5-second timer turn it
back off. Off is a software-enforced display state, not an electrical disconnect;
short wake flashes may still occur. Touch input remains active. Check that
another Touch Bar utility is not fighting the setting.

## Unsupported system or refused brightness changes

The release is arm64-only and requires a physical Touch Bar. It dynamically
loads CoreBrightness/DFRBrightness and checks their interfaces and selected
properties. An OS update can break these private contracts. Granting
Accessibility or Full Disk Access cannot fix a missing private selector.

The menu shows a warning if macOS rejects a brightness write. Quit other
brightness utilities, reopen this app, and inspect **Diagnostics… → Show report**:

```sh
build/FlickOff.app/Contents/MacOS/FlickOff --diagnose
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

## Reporting problems and privacy

Open an issue with the app version, Mac model, OS version, mode and whether higher
brightness or Off helped. Review diagnostic reports before attaching them. Do
not include serial numbers, credentials or unrelated system logs.

Reports collect model/chip/OS, selected numeric backlight properties, private API
method signatures and selected brightness values. They exclude the broad
`StatusInfo` dump and arbitrary registry properties. UUIDs are replaced with
consistent labels. Nothing uploads automatically: Copy and Save stay local.


## “App Update Required” or a Rosetta warning

Install the current Apple silicon build. The release executable must report
`arm64` with `lipo -archs`; it does not need Rosetta. Version 1.0.1 explicitly
requires native execution and verifies the architecture during packaging.
Intel smoke-test bundles are restricted to native Intel CI and have a separate
Build Check identity so they cannot be mistaken for the release app.

This warning can be triggered by an older Intel test build with the same app
identity. Check the installed binary rather than assuming the current release
uses an Intel component. Do not disable system compatibility warnings or remove
Rosetta from the system to work around an incorrectly built app.
