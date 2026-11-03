#!/usr/bin/env python3
"""Run the checks hosted CI can't, on the Mac with the Touch Bar and the signing key, and record the pass.

make_release.py requires a pass for the commit it releases. This is deliberately not a self-hosted
runner: the repository is public, and a runner would let code from a fork's pull request run on this Mac.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULT = ROOT / 'build/preflight.json'
BUNDLE_ID = 'io.github.ZheMaxy.FlickOff'


def output(*args):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, check=False).stdout.strip()


def running_app():
    """The bundle of the copy running now, so it can be reopened afterwards."""
    pid = output('pgrep', '-x', 'FlickOff').split('\n')[0]
    binary = output('ps', '-o', 'comm=', '-p', pid) if pid else ''
    return binary.split('/Contents/MacOS/')[0] if '/Contents/MacOS/' in binary else None


def quit_running_app():
    subprocess.run(['osascript', '-e', f'tell application id "{BUNDLE_ID}" to quit'], capture_output=True, check=False)
    end = time.monotonic() + 10
    while output('pgrep', '-x', 'FlickOff') and time.monotonic() < end:
        time.sleep(0.2)
    if output('pgrep', '-x', 'FlickOff'):
        raise SystemExit('FlickOff did not quit; quit every copy and try again')


def reopen(app):
    """Waits for it, because the next step needs to find it running to put it back afterwards."""
    subprocess.run(['open', '-g', app], check=False)
    end = time.monotonic() + 10
    while not output('pgrep', '-x', 'FlickOff') and time.monotonic() < end:
        time.sleep(0.2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, help='A CI-built app for the built-app checks, instead of the local build')
    parser.add_argument('--root-owned', action='store_true', help='Also update a root-owned copy; asks for an administrator')
    args = parser.parse_args()
    if output('git', '-C', ROOT, 'status', '--porcelain'):
        raise SystemExit('Commit your changes first: a pass has to describe a commit')
    commit = output('git', '-C', ROOT, 'rev-parse', 'HEAD')
    passed = []

    def step(name, *command, **environment):
        print(f'\n-- {name}', flush=True)
        subprocess.run([str(c) for c in command], cwd=ROOT, env={**os.environ, **environment}, check=True)
        passed.append(name)

    step('Tests, bundle and smoke checks', './build.sh')
    previous = running_app()
    if previous:
        quit_running_app()
    try:
        step('Hardware tests', './build.sh', 'test', TB_HARDWARE_TESTS='1')
    finally:
        if previous:
            reopen(previous)
    integration = [sys.executable, 'Tests/Integration/run.py']
    if args.app:
        integration += ['--app', args.app.resolve()]
    step('Built-app integration checks', *integration)
    with tempfile.TemporaryDirectory(prefix='flickoff-preflight-') as temp:
        step('Native installer', sys.executable, 'scripts/make_installer.py', '--output', temp)
        package, image = next(Path(temp).glob('*.pkg')), next(Path(temp).glob('*.dmg'))
        step('Installer checks', sys.executable, 'Tests/Integration/installer_test.py', '--pkg', package, '--dmg', image)
    step('Signed update checks', sys.executable, 'Tests/Integration/update_test.py')
    if args.root_owned:
        step('Update of a root-owned copy', sys.executable, 'Tests/Integration/update_test.py', '--root-owned')
    RESULT.parent.mkdir(exist_ok=True)
    RESULT.write_text(json.dumps({
        'commit': commit,
        'date': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'passed': passed,
    }, indent=2) + '\n')
    print(f'\nPreflight passed for {commit[:7]}: {len(passed)} steps.')


if __name__ == '__main__':
    main()
