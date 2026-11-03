#!/usr/bin/env python3
"""Verify signed feed discovery, tamper rejection and Sparkle installation in temp copies."""
import argparse
from functools import partial
import http.server
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def run(*args, timeout=60, check=True):
    r = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
    if check and r.returncode:
        raise RuntimeError(r.stdout + r.stderr)
    return r


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def as_root(script):
    """Runs a shell script through the standard administrator prompt, which a person must answer."""
    quoted = script.replace('\\', '\\\\').replace('"', '\\"')
    run('osascript', '-e', f'do shell script "{quoted}" with administrator privileges', timeout=180)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root-owned', action='store_true',
                        help='Update a copy owned by root, as the installer leaves it. Asks for an administrator three times.')
    args = parser.parse_args()
    app = ROOT / 'build/FlickOff.app'
    current_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    current_build = current_info['CFBundleVersion']
    old_build = str(int(current_build) - 1)
    current_version = current_info['CFBundleShortVersionString']
    framework = app / 'Contents/Frameworks'
    signer = ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
    account = 'io.github.ZheMaxy.FlickOff'
    with tempfile.TemporaryDirectory(prefix='flickoff-updater-') as temp:
        temp = Path(temp)
        probe = temp / 'update-probe'
        run('xcrun', 'clang', '-fobjc-arc', '-framework', 'AppKit', '-F', framework,
            '-framework', 'Sparkle', '-Wl,-rpath,' + str(framework),
            ROOT / 'Tests/Integration/UpdateProbe.m', '-o', probe)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(temp)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        test_ids = []

        def fixture(name):
            case = temp / name
            prefix = f'http://127.0.0.1:{server.server_port}/{name}/release'
            test_id = account + '.UpdateTest.' + uuid.uuid4().hex
            test_ids.append(test_id)
            newer = case / 'new/FlickOff.app'
            older = case / 'old/FlickOff.app'
            run('ditto', app, newer)
            info_path = newer / 'Contents/Info.plist'
            info = plistlib.loads(info_path.read_bytes())
            info['CFBundleIdentifier'] = test_id
            info['SUFeedURL'] = prefix + '/appcast.xml'
            info['SUEnableAutomaticChecks'] = False
            info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
            info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
            run('codesign', '--force', '--sign', '-', newer)
            run('ditto', newer, older)
            older_info = dict(info, CFBundleVersion=old_build, CFBundleShortVersionString='1.0.0')
            (older / 'Contents/Info.plist').write_bytes(plistlib.dumps(older_info, sort_keys=False))
            run('codesign', '--force', '--sign', '-', older)
            run('python3', ROOT / 'scripts/make_release.py', '--archive-only', '--app', newer, '--tag', 'test',
                '--output', case / 'release', '--download-prefix', prefix, timeout=90)
            return older, case / 'release'

        try:
            if args.root_owned:
                older, release = fixture('root-owned')
                parent = shlex.quote(str(older.parent))
                as_root(f'/usr/sbin/chown -R root:wheel {parent}')
                try:
                    # Sparkle asks for the administrator itself while the probe waits.
                    r = run(probe, older, 'install-privileged', check=False, timeout=200)
                    deadline = time.monotonic() + 20
                    while time.monotonic() < deadline:
                        installed = plistlib.loads((older / 'Contents/Info.plist').read_bytes())
                        if installed['CFBundleVersion'] == current_build:
                            break
                        time.sleep(0.2)
                    else:
                        raise AssertionError('Update did not install: ' + r.stdout + r.stderr)
                    run('codesign', '--verify', '--deep', '--strict', older)
                    assert older.stat().st_uid == 0, 'the update changed who owns the app'
                    print('PASS: Sparkle updates a root-owned app after administrator approval', flush=True)
                finally:
                    as_root(f'/bin/rm -rf {parent}')
                return

            older, release = fixture('discovery')
            r = run(probe, older, 'probe')
            assert 'FOUND ' + current_build in r.stdout, r.stdout + r.stderr
            print('PASS: Sparkle discovers a newer build from a valid signed feed', flush=True)

            older, release = fixture('feed')
            feed = release / 'appcast.xml'
            feed.write_bytes(feed.read_bytes().replace(b'FlickOff Updates', b'FakeOff Updates', 1))
            r = run(probe, older, 'reject')
            assert 'REJECTED_SIGNATURE' in r.stdout, r.stdout + r.stderr
            print('PASS: Sparkle rejects a tampered feed', flush=True)

            older, release = fixture('archive')
            archive = release / f'FlickOff-{current_version}-arm64.zip'
            damaged = bytearray(archive.read_bytes())
            damaged[len(damaged)//2] ^= 1
            archive.write_bytes(damaged)
            r = run(probe, older, 'reject-archive')
            assert 'REJECTED_SIGNATURE' in r.stdout, r.stdout + r.stderr
            assert plistlib.loads((older / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == old_build
            print('PASS: Sparkle rejects a tampered archive before installing it', flush=True)

            older, release = fixture('install')
            r = run(probe, older, 'install', check=False)
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                installed = plistlib.loads((older / 'Contents/Info.plist').read_bytes())
                if installed['CFBundleVersion'] == current_build:
                    break
                time.sleep(0.2)
            else:
                raise AssertionError('Update did not install: ' + r.stdout + r.stderr)
            run('codesign', '--verify', '--deep', '--strict', older)
            assert run('lipo', '-archs', older / 'Contents/MacOS/FlickOff').stdout.strip() == 'arm64'
            print('PASS: Sparkle downloads and installs the valid update into a temporary app', flush=True)
        finally:
            server.shutdown()
            server.server_close()
            library = Path.home() / 'Library'
            for test_id in test_ids:
                run('defaults', 'delete', test_id, check=False)
                # What macOS and Sparkle keep per identity, which would pile up with each random test id.
                (library / 'Preferences' / f'{test_id}.plist').unlink(missing_ok=True)
                for place in ('Caches', 'HTTPStorages'):
                    shutil.rmtree(library / place / test_id, ignore_errors=True)



if __name__ == '__main__':
    main()
