# Built-application integration checks

Run locally on a supported Mac with a Touch Bar, while awake, unlocked and open:

```sh
./build.sh
python3 Tests/Integration/run.py
```

Requires Python 3 and Xcode/Command Line Tools. Do not run this script in hosted
CI or concurrently with the hardware unit suite. Keep the test Mac available:
the panel briefly changes brightness, dims and turns off. The minimum-brightness
case may cause flickering.

This tests the **built menu bar app as a separate process**, not a fake controller:

- Manual/Auto/Off at real application launch.
- Timer recovery from an external brightness change.
- Recovery after the actual Touch Bar service dims or powers off the panel.
- Leaving service dimming intact with prevention disabled.
- Brightness restoration after normal application quit.
- Re-enforcement of Off after an external wake, and cleanup on SIGTERM.
- Validation of out-of-range stored brightness values.

The helper is compiled into a temporary directory from the same Objective-C
bridge as the app. It reads panel state and performs explicit test writes. It
never becomes part of the app bundle.

The script temporarily quits one running copy, saves panel state and preferences,
uses typed preference fixtures, then restores them and reopens the original app.
It refuses to start with multiple running copies. Avoid changing app settings
while the script runs. Normal exceptions, Ctrl-C and SIGTERM trigger cleanup;
force-killing the script or losing power cannot guarantee restoration.

An alternative bundle can be supplied with `--app /path/to/FlickOff.app`.
Tests do not log out, reboot, lock the screen or close the lid. Service-injected
dimming/power-off verifies recovery from those states; it is not a measurement of
natural idle timing. Actual login, lock/unlock, sleep/wake and closed-lid behaviour
require a coordinated system test with a person available to unlock the Mac.


## Software updater

`python3 Tests/Integration/update_test.py` exercises Sparkle's signed feed,
archive validation and installation in isolated temporary bundles. It requires
the release owner's Keychain signing key; it does not operate the installed app
or Touch Bar. Each case uses a fresh identity so installer recovery state from a
negative case cannot affect a later successful installation.

## Installer

```sh
python3 scripts/make_installer.py --output build/installer-check
python3 Tests/Integration/installer_test.py --pkg build/installer-check/*.pkg --dmg build/installer-check/*.dmg
```

These checks expand the package, verify app/framework signatures and native
architecture, evaluate Installer requirements without installing, and execute
upgrade guards against isolated fixtures. Postinstall launch routing is checked
with stubbed system commands. The disk image is mounted read-only and the native
installer's read-only self-test is run. No administrator access or panel writes
are involved. CI performs these checks with its separate native Intel identity.

Actual installation and its administrator prompt require a coordinated local
test. Verify the existing app quits, settings survive replacement, FlickOff
opens as the console user, and login/update preferences retain their values.
