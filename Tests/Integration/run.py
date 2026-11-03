#!/usr/bin/env python3
"""Exercise the built menu bar app against real Touch Bar services; restore state."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
DOMAIN = "io.github.ZheMaxy.FlickOff"


def run(*args, check=True):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=30)
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} exited {result.returncode}: {result.stderr.strip()}")
    return result


def app_pids():
    result = run("pgrep", "-x", "FlickOff", check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError("Cannot inspect running app processes")
    return [int(pid) for pid in result.stdout.split()]


def process_app(pid):
    lib = ctypes.CDLL("/usr/lib/libproc.dylib")
    buf = ctypes.create_string_buffer(4096)
    if lib.proc_pidpath(pid, buf, len(buf)) <= 0:
        raise RuntimeError("Cannot resolve running app path")
    binary = Path(os.fsdecode(buf.value))
    if binary.parent.name != "MacOS" or binary.parent.parent.name != "Contents":
        raise RuntimeError("Running process is not an app bundle; quit it before testing")
    return binary.parents[2]


def interrupted(_signal, _frame):
    raise KeyboardInterrupt("Integration test interrupted; restoring app state")


def preferences():
    result = run("defaults", "export", DOMAIN, "-", check=False)
    return plistlib.loads(result.stdout.encode()) if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build/FlickOff.app")
    args = parser.parse_args()
    binary = args.app.resolve() / "Contents/MacOS/FlickOff"
    if not binary.is_file():
        parser.error("Build the application with ./build.sh first")
    pids = app_pids()
    if len(pids) > 1:
        parser.error("Quit duplicate copies before testing")
    previous_app = process_app(pids[0]) if pids else None
    signal.signal(signal.SIGTERM, interrupted)
    saved_preferences = preferences()
    passed = []
    active = None

    with tempfile.TemporaryDirectory(prefix="touchbar-integration-") as temp:
        temp = Path(temp)
        probe = temp / "panel-probe"
        run("xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", "-framework", "AppKit",
            "-framework", "CoreGraphics", "-framework", "IOKit",
            "-I", ROOT / "Sources/TBPrivate/include", ROOT / "Sources/TBPrivate/TBTouchBar.m",
            ROOT / "Tests/Integration/PanelProbe.m", "-o", probe)

        def state():
            return json.loads(run(probe, "snapshot").stdout)

        def wait(predicate, message, timeout=4):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                if predicate(state()):
                    return
                if active is not None and active.poll() is not None:
                    raise AssertionError("Application exited before " + message)
                time.sleep(0.1)
            raise AssertionError(message + "; observed " + json.dumps(state()))

        def check(name):
            passed.append(name)
            print("PASS:", name, flush=True)

        def stop(pid):
            run(probe, "quit", pid)
            end = time.monotonic() + 5
            while pid in app_pids() and time.monotonic() < end:
                time.sleep(0.1)
            if pid in app_pids():
                raise RuntimeError("App did not quit; refusing to start a competing copy")

        def launch(mode, level="0.8", prevent=True, idle=0):
            nonlocal active
            before = state()
            fixture = dict(saved_preferences or {})
            fixture.update(mode=mode, level=float(level), preventDimming=prevent, idleOffSeconds=idle,
                           loginItemConfigured=True, SUEnableAutomaticChecks=False)
            fixture_path = temp / "fixture.plist"
            fixture_path.write_bytes(plistlib.dumps(fixture))
            run("defaults", "import", DOMAIN, fixture_path)
            active = subprocess.Popen([str(binary)], stdout=log, stderr=log)
            return before

        def expect_restored(before):
            wait(lambda s: s["auto"] == before["auto"] and
                 (before["auto"] or abs(s["level"] - before["level"]) < 0.02),
                 "launch-time brightness was not restored")

        def finish(before, terminate=False):
            nonlocal active
            if terminate:
                active.send_signal(signal.SIGTERM)
            else:
                run(probe, "quit", active.pid)
            active.wait(timeout=5)
            if active.returncode != 0:
                raise AssertionError("App exited with code " + str(active.returncode))
            active = None
            expect_restored(before)

        original = state()
        if original["locked"] or original["lidClosed"] or original["displayAsleep"]:
            parser.error("The Mac must be awake, unlocked and open")
        restore_file = temp / "original.json"
        restore_file.write_text(json.dumps(original))
        with (temp / "app.log").open("w") as log:
            try:
                if pids:
                    stop(pids[0])
                before = launch("manual")
                wait(lambda s: not s["auto"] and abs(s["level"] - 0.8) < 0.02, "manual launch")
                check("built app applies Manual brightness at launch")
                run(probe, "level", "0.45")
                wait(lambda s: abs(s["level"] - 0.8) < 0.02, "brightness drift recovery", timeout=7)
                check("running app recovers externally changed brightness through its timer")
                run(probe, "dim")
                wait(lambda s: s["step"] == 0, "dimming recovery")
                check("running app undoes actual service dimming")
                run(probe, "off")
                wait(lambda s: s["panel"] == 2, "panel wake after idle-style power-off")
                check("running app recovers after service turns its panel off")
                finish(before)
                check("normal application quit restores launch-time brightness")

                before = launch("auto")
                wait(lambda s: s["auto"], "Auto launch")
                finish(before)
                check("Auto mode starts and restores prior settings on quit")

                before = launch("off")
                wait(lambda s: s["panel"] == 1, "Off launch")
                run(probe, "on")
                wait(lambda s: s["panel"] == 1, "Off re-enforcement")
                finish(before, terminate=True)
                wait(lambda s: s["panel"] == 2, "Off panel release on SIGTERM")
                check("Off survives external wake and SIGTERM releases the panel")

                before = launch("manual", prevent=False)
                wait(lambda s: not s["auto"] and abs(s["level"] - 0.8) < 0.02, "manual launch without prevention")
                run(probe, "dim")
                wait(lambda s: s["step"] > 0, "service dimming with prevention disabled")
                time.sleep(0.8)
                assert state()["step"] > 0, "app undid dimming while prevention was disabled"
                finish(before)
                check("disabled dimming prevention leaves the service's dimming intact")

                for raw, expected in [("-1", 0), ("2", 1)]:
                    before = launch("manual", raw)
                    wait(lambda s: abs(s["level"] - expected) < 0.02, "saved brightness range clamping")
                    finish(before)
                check("real app clamps out-of-range launch preferences")

                # Needs the test Mac left alone for a few seconds at a time.
                before = launch("manual", idle=5)
                wait(lambda s: s["panel"] == 1, "idle power-off", timeout=120)
                check("running app turns the panel off after the idle delay")
                if run(probe, "input", check=False).returncode == 0:
                    wait(lambda s: s["panel"] == 2, "panel wake on input", timeout=2)
                    check("input lights a panel turned off for idleness")
                    wait(lambda s: s["panel"] == 1, "idle power-off after input", timeout=120)
                else:
                    print("SKIP: posting input needs Accessibility access", flush=True)
                run(probe, "on")
                time.sleep(2)
                assert state()["panel"] == 2, "panel lit from outside went dark again before the idle delay"
                wait(lambda s: s["panel"] == 1, "idle power-off after an outside wake", timeout=120)
                check("a panel lit from outside, as by a touch, gets another idle delay")
                finish(before, terminate=True)
                wait(lambda s: s["panel"] == 2, "panel release on SIGTERM during idle power-off")
                check("SIGTERM gives back a panel turned off for idleness")

                before = launch("manual")
                wait(lambda s: not s["auto"] and abs(s["level"] - 0.8) < 0.02, "manual launch before a second copy")
                second = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
                assert second.returncode == 0, second.stderr
                assert active.poll() is None, "second copy stopped the running app"
                check("a second copy exits and leaves the running app in charge")
                end = time.monotonic() + 4
                while int(run(probe, "windows", active.pid).stdout) < 1 and time.monotonic() < end:
                    time.sleep(0.1)
                assert int(run(probe, "windows", active.pid).stdout) == 1, "reopening did not show a window"
                check("opening the running app again shows its controls in a window")
                finish(before)

            finally:
                if active is not None and active.poll() is None:
                    active.send_signal(signal.SIGTERM)
                    try:
                        active.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        active.kill()  # Only the test process created above.
                        active.wait(timeout=5)
                try:
                    run(probe, "restore", restore_file)
                finally:
                    # Import can retain keys introduced by the app or updater.
                    # Clear the test domain before restoring its exact snapshot.
                    run("defaults", "delete", DOMAIN, check=False)
                    if saved_preferences is not None:
                        original_preferences = temp / "original-preferences.plist"
                        original_preferences.write_bytes(plistlib.dumps(saved_preferences))
                        run("defaults", "import", DOMAIN, original_preferences)
                    assert preferences() == saved_preferences, "original preferences were not restored"
                    if previous_app:
                        run("open", "-g", previous_app)
        check("original user preferences are restored")
        print(json.dumps({"passed": len(passed), "checks": passed, "previous_app_reopened": bool(previous_app)}))


if __name__ == "__main__":
    main()
