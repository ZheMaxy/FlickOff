# Validation status

Validated on **2026-11-03**, using an M1 13-inch MacBook Pro (2020),
`MacBookPro17,1`, macOS 27.2.0 (26B123), Swift 6.4.2, arm64.

## Automated checks

`TB_HARDWARE_TESTS=1 ./build.sh test` passed **all 84 test functions in 14 suites**,
including parameterized cases. The installed app was quit first and reopened
afterward.

Live hardware checks passed:

- Read-only framework/selector, property and display compatibility checks.
- Auto-brightness enable/disable and manual brightness round trips at 50%/80%.
- Panel off/on state transitions.
- Off/on, brightness and dimming-coefficient probes, with settings restoration.

Controller tests also cover invalid preferences/telemetry, rejected writes,
diagnostic pauses, observer/timer cleanup, restoring settings at quit, and
preventing panel wake during sleep, lock or a closed lid. These lifecycle states
are tested with fakes; real sleep/lock/lid sequences still need coordinated system validation.

The arm64 release bundle builds successfully. Its ad-hoc signature, plist/string
files, setup CLI smoke test, workflow YAML and local documentation links were
checked. An earlier CI run passed on a GitHub-hosted ARM macOS runner. Later
runs were cancelled before any step ran because GitHub could not allocate an
ARM runner; this was not a build or test failure.

CI now uses the explicit `macos-15-intel` pool. It runs ordinary tests and a native
x86_64 bundle smoke check, then separately cross-compiles the arm64 release target.
`TB_BUILD_ARCH=x86_64` is accepted only on native Intel CI, whose bundle uses a
separate `io.github.ZheMaxy.FlickOff.BuildCheck` identifier. Local builds require
arm64 and the app requests native execution without Rosetta. The build verifies
the resulting Mach-O architecture. This does not establish support for Intel Touch Bar hardware.
Check the latest commit's CI status for its result.

## Built-application integration

On the same M1/macOS 27.2 machine, `python3 Tests/Integration/run.py` passed
**10 integration checks** against the built release app running as its own
process. These verify startup in Manual/Auto/Off, recovery from brightness drift,
actual service dimming/power-off, prevention disabled, normal quit, SIGTERM,
invalid stored levels, and restoration of user preferences. The previously
running installed app was reopened afterward.

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

## What this does not establish

API return values and reported state do not measure visible light output. These
tests do not prove that flickering has stopped on another panel or that hardware
is repaired. The original workaround is based on the author's observed
low-brightness flicker.

M2, Intel and older macOS versions were not validated on hardware. macOS 13 is
the deployment floor, not a tested compatibility matrix. Developer ID signing
and notarization have not been performed; local bundles use an ad-hoc signature.

Before declaring a stable binary release, perform the manual checks in
[RELEASING.md](RELEASING.md), including idle/wake/lock/login behaviour.
