#!/usr/bin/env python3
"""Inspect a native installer and exercise upgrade guards without installing it."""
import argparse
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET


def run(*args, check=True):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=60)
    if check and result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pkg', type=Path, required=True)
    parser.add_argument('--dmg', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='flickoff-installer-test-') as temp:
        temp = Path(temp)
        expanded = temp / 'expanded'
        run('pkgutil', '--expand-full', args.pkg, expanded)
        components = list(expanded.glob('*.pkg'))
        assert len(components) == 1
        component = components[0]
        payload = component / 'Payload'
        assert {path.name for path in payload.iterdir()} == {'FlickOff.app'}
        app = payload / 'FlickOff.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        run('codesign', '--verify', '--deep', '--strict', app)
        arch = run('lipo', '-archs', app / 'Contents/MacOS/FlickOff').stdout.strip()
        framework = app / 'Contents/Frameworks/Sparkle.framework'
        for path in framework.rglob('*'):
            if path.is_file() and not path.is_symlink() and 'Mach-O' in run('file', '-b', path).stdout:
                run('lipo', path, '-verify_arch', arch)
        print('PASS:', 'app-only payload, deep signature and native Sparkle helpers')

        distribution = ET.parse(expanded / 'Distribution').getroot()
        assert distribution.find('options').attrib['hostArchitectures'] == arch
        assert distribution.find('./volume-check/allowed-os-versions/os-version').attrib['min'] == info['LSMinimumSystemVersion']
        assert distribution.find('domains').attrib == {
            'enable_anywhere': 'false', 'enable_currentUserHome': 'false', 'enable_localSystem': 'true'}
        assert distribution.find('license') is None
        assert not (expanded / 'Plugins').exists()
        for name in ('welcome', 'conclusion'):
            assert (expanded / 'Resources' / distribution.find(name).attrib['file']).is_file()
        package_info = ET.parse(component / 'PackageInfo').getroot()
        assert package_info.attrib['install-location'] == '/Applications'
        assert package_info.attrib['relocatable'] == 'false'
        assert package_info.find('./upgrade-bundle/bundle').attrib['id'] == info['CFBundleIdentifier']
        assert package_info.find('./strict-identifier/bundle').attrib['id'] == info['CFBundleIdentifier']
        # Only evaluates the native Installer's UI/requirements; no payload or scripts run.
        choices = plistlib.loads(run('installer', '-pkg', args.pkg, '-target', '/', '-showChoicesXML').stdout.encode())
        assert choices
        print('PASS:', 'native requirements, startup disk and upgrade metadata; no GUI plugins')

        script = (component / 'Scripts/preinstall').read_text()
        assert '@BUILD@' not in script and '@BUNDLE_ID@' not in script
        assert script.count('app=/Applications/FlickOff.app\n') == 1
        fixture = temp / 'FlickOff.app'
        script = script.replace('app=/Applications/FlickOff.app\n', 'app=' + shlex.quote(str(fixture)) + '\n')
        expected_line = "expected_id='" + info['CFBundleIdentifier'] + "'\n"
        assert script.count(expected_line) == 1
        test_id = 'example.installer-test.' + uuid.uuid4().hex
        script = script.replace(expected_line, 'expected_id=' + shlex.quote(test_id) + '\n')
        isolated = temp / 'preinstall'
        isolated.write_text(script)
        run('/bin/sh', '-n', isolated)
        assert run('/bin/sh', isolated, 'package', '/Applications', '/other-volume', check=False).returncode != 0
        assert run('/bin/sh', isolated, 'package', '/Applications', '/').returncode == 0
        fixture.symlink_to(temp / 'another-app')
        assert run('/bin/sh', isolated, 'package', '/Applications', '/', check=False).returncode != 0
        fixture.unlink()
        (fixture / 'Contents').mkdir(parents=True)
        info_path = fixture / 'Contents/Info.plist'
        for build, identifier, allowed in [
            ('1', test_id, True),
            (info['CFBundleVersion'], test_id, True),
            (str(int(info['CFBundleVersion']) + 1), test_id, False),
            ('99999999999999999999', test_id, False),
            ('invalid', test_id, False),
            ('1', 'example.another-app', False),
        ]:
            info_path.write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier, 'CFBundleVersion': build}))
            result = run('/bin/sh', isolated, 'package', '/Applications', '/', check=False)
            assert (result.returncode == 0) == allowed, result.stderr
        print('PASS:', 'fresh install/reinstall/upgrade allowed; downgrade, foreign app, invalid build and symlink rejected')

        postinstall = (component / 'Scripts/postinstall').read_text()
        stat = temp / 'console-user'
        value = temp / 'console-uid'
        stat.write_text('#!/bin/sh\ncat ' + shlex.quote(str(value)) + '\n')
        stat.chmod(0o755)
        launch = temp / 'launch-in-session'
        log = temp / 'launch.log'
        launch.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > " + shlex.quote(str(log)) + '\n')
        launch.chmod(0o755)
        postinstall = postinstall.replace('/usr/bin/stat', shlex.quote(str(stat))).replace('/bin/launchctl', shlex.quote(str(launch)))
        post = temp / 'postinstall'
        post.write_text(postinstall)
        for uid in ('0', '1', 'invalid', ''):
            value.write_text(uid)
            run('/bin/sh', post, 'package', '/Applications', '/')
            assert not log.exists()
        value.write_text('501')
        run('/bin/sh', post, 'package', '/Applications', '/')
        assert log.read_text().splitlines() == ['asuser', '501', '/usr/bin/sudo', '-u', '#501',
                                               '/usr/bin/open', '-g', '/Applications/FlickOff.app']
        print('PASS:', 'post-install launch selects the console user, drops root and skips inactive sessions')

        if args.dmg:
            mount = temp / 'mounted'
            mount.mkdir()
            run('hdiutil', 'attach', args.dmg, '-readonly', '-nobrowse', '-mountpoint', mount)
            try:
                installer = mount / 'Install FlickOff.app'
                run('codesign', '--verify', '--deep', '--strict', installer)
                run('lipo', installer / 'Contents/MacOS/FlickOffInstaller', '-verify_arch', arch)
                assert 'valid' in run(installer / 'Contents/MacOS/FlickOffInstaller', '--self-test').stdout
                assert (installer / 'Contents/Resources/FlickOff.pkg').read_bytes() == args.pkg.read_bytes()
                assert (installer / 'Contents/Resources/license.txt').stat().st_size > 100
            finally:
                run('hdiutil', 'detach', mount)
            print('PASS:', 'disk image contains the signed native installer and identical package payload')


if __name__ == '__main__':
    main()
