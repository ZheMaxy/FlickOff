# Validation status

Validated on **2026-11-04**, using an M1 13-inch MacBook Pro (2020),
`MacBookPro17,1`, macOS 27.2.0 (26B123), Swift 6.4.2, arm64.

## Automated checks

`TB_HARDWARE_TESTS=1 ./build.sh test` passed **all 150 test functions in 22 suites**,
including parameterized cases. The installed app was quit first and reopened
afterward.

Live hardware checks passed:

- Read-only framework/selector, property and display compatibility checks.
- Auto-brightness enable/disable and manual brightness round trips at 50%/80%.
- Panel off/on state transitions.
- Off/on, brightness and dimming-coefficient probes, with settings restoration.
- On/off/undim calls report success, also when there is nothing to change, so a
  refusal can be told apart.
- Brightness settings, console ownership and idle time read correctly.

Controller tests also cover invalid preferences/telemetry, rejected writes,
diagnostic pauses, observer/timer cleanup, restoring settings at quit, and
preventing panel wake during sleep, lock or a closed lid, plus idle power-off,
reconnecting after a failed launch check, unreadable brightness, quitting during
a probe, refused panel calls, fast user switching and staying silent while nothing
changes. These lifecycle states are tested with fakes; real sleep/lock/lid/login
and user-switching sequences still need coordinated system validation.

The arm64 release bundle builds successfully. Its ad-hoc signature, plist/string
files, setup CLI smoke test, workflow YAML and local documentation links were
checked.

Every push runs the tests with the read-only private API contract, the bundle smoke
check and the installer checks natively on arm64 on `macos-15`. `macos-26` runs the
tests weekly as well. Selector checks passing on those images say nothing about whether
writes work there. The result for the latest commit is on its CI status.

## Built-application integration

On the same M1/macOS 27.2 machine, `python3 Tests/Integration/run.py` passed
**16 integration checks** against the built release app running as its own
process. These verify startup in Manual/Auto/Off, recovery from brightness drift,
actual service dimming/power-off, prevention disabled, normal quit, SIGTERM,
invalid stored levels, idle power-off with real posted input and an outside wake,
a second copy exiting, the controls window on reopening, and restoration of user
preferences. The previously running installed app was reopened afterward.

## The real menu

Driven with real clicks on the same machine: the slider, the **When idle** list,
Auto/Manual/Off, opening and closing the menu with one click, and Quit. The light
output in the header followed a slider change while the menu stayed open. Opening
Diagnostics closes the menu. A probe started in Off lit the panel, went dark, came
back for a moment and returned to Off. VoiceOver names the icon FlickOff.

A temporary copy with a loopback feed showed a scheduled update on the menu bar
icon and as a button in the menu, with no alert until that button was pressed.

## Energy use

With the menu closed and nothing changing, `top` over 60 seconds on battery measured
about **0.10% CPU**, down from about 2.2% for build 4 in the same conditions.

The current login-item status is enabled; this read-only check does not establish
that an actual logout/login cycle launches the app correctly.

Instructions and cleanup details: [integration checks](../Tests/Integration/README.md).

## Signed update checks

The pinned Sparkle integration passed four local checks using isolated temporary
bundles and a loopback feed: newer-build discovery, rejection of a modified
signed feed, rejection of a modified archive before installation, and successful
download/installation of a valid signed update. The test does not replace the
installed app or exercise its Touch Bar controller.

Reproduce with `python3 Tests/Integration/update_test.py`. This requires the
owner's release-signing key in Keychain and is not run in hosted CI.

`--root-owned` passed too: Sparkle replaced a temporary copy owned by root, as the
installer leaves the real app, after administrator approval. Ownership and the
code signature were intact afterward.

## Native installer

Five local installer checks passed: signed app-only package payload and native
helpers; system requirements and upgrade metadata; isolated install/upgrade and
rejection guards; launching in the console user's session after dropping root;
and mounting the disk image to verify the native installer and embedded package.
These checks also run in CI without installation or administrator access.

The native installer was then used on this Mac to replace an existing copy.
It preserved brightness/mode/preferences and opened build 4 automatically as
the console user, UID 501. Login-item status was enabled with no setup issues,
and automatic update checking was enabled. The inline license screen and
Agree and Install action were reviewed during this test. No Installer GUI
plugins are included.

This verifies registration state and immediate launch; an actual logout/login
cycle has not been performed.

## What this does not establish

Not yet tried on real hardware: updating the actual installed app and checking its
login item afterward, a real logout/login cycle, reconnecting when services really
start late, a second user with fast user switching, and what touching a dark panel
does. An outside wake is simulated by turning the panel on through the service.

API return values and reported state do not measure visible light output. These
tests do not prove that flickering has stopped on another panel or that hardware
is repaired. The original workaround is based on the author's observed
low-brightness flicker.

M2, Intel and older macOS versions were not validated on hardware. macOS 13 is
the deployment floor, not a tested compatibility matrix. Developer ID signing
and notarization have not been performed; local bundles use an ad-hoc signature.

Before declaring a stable binary release, perform the manual checks in
[RELEASING.md](RELEASING.md), including idle/wake/lock/login behaviour.
