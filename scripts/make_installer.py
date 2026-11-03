#!/usr/bin/env python3
"""Build the native macOS Installer product for FlickOff, preserving app signatures."""
import argparse
import base64
import hashlib
import html
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/FlickOff.app')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sign-identity', help='Developer ID Installer identity in Keychain')
    parser.add_argument('--app-sign-identity', help='Developer ID Application identity for the installer window')
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    bundle_id = info['CFBundleIdentifier']
    arch = run('lipo', '-archs', app / 'Contents/MacOS/FlickOff').strip()
    if bundle_id != 'io.github.ZheMaxy.FlickOff' or arch != 'arm64':
        raise SystemExit('Only the arm64 release can be packaged')
    if not isinstance(version, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version):
        raise SystemExit('CFBundleShortVersionString must be a dotted numeric version')
    if not isinstance(build, str) or not build.isascii() or not build.isdecimal() or len(build) > 9:
        raise SystemExit('CFBundleVersion must be a positive numeric build number')
    if int(build) <= 0:
        raise SystemExit('CFBundleVersion must be positive')
    if args.sign_identity and not args.sign_identity.startswith('Developer ID Installer:'):
        raise SystemExit('Use a Developer ID Installer identity for installer signing')
    if args.app_sign_identity and not args.app_sign_identity.startswith('Developer ID Application:'):
        raise SystemExit('Use a Developer ID Application identity for the installer app')
    run('codesign', '--verify', '--deep', '--strict', app)
    args.output.mkdir(parents=True, exist_ok=True)
    output = args.output.resolve() / f'FlickOff-{version}-{arch}.pkg'
    image = output.with_suffix('.dmg')
    if output.exists() or image.exists():
        raise SystemExit('Installer already exists; use a fresh output directory')
    with tempfile.TemporaryDirectory(prefix='flickoff-package-') as temp:
        temp = Path(temp)
        payload = temp / 'payload'
        scripts = temp / 'scripts'
        resources = temp / 'resources'
        for directory in (payload, scripts, resources):
            directory.mkdir()
        run('ditto', app, payload / 'FlickOff.app')
        components = [{
            'RootRelativeBundlePath': 'FlickOff.app',
            'BundleIsRelocatable': False,
            'BundleIsVersionChecked': False,
            'BundleHasStrictIdentifier': True,
            'BundleOverwriteAction': 'upgrade',
        }]
        component_plist = temp / 'components.plist'
        component_plist.write_bytes(plistlib.dumps(components))
        preinstall = (ROOT / 'Packaging/Installer/preinstall').read_text()
        preinstall = preinstall.replace('@BUILD@', build).replace('@BUNDLE_ID@', bundle_id)
        (scripts / 'preinstall').write_text(preinstall)
        (scripts / 'preinstall').chmod(0o755)
        (scripts / 'postinstall').write_text((ROOT / 'Packaging/Installer/postinstall').read_text())
        (scripts / 'postinstall').chmod(0o755)
        component = temp / 'FlickOff-component.pkg'
        run('pkgbuild', '--root', payload, '--component-plist', component_plist,
            '--identifier', bundle_id + '.pkg', '--version', version,
            '--install-location', '/Applications', '--ownership', 'recommended',
            '--compression', 'legacy', '--scripts', scripts, component)
        requirements = temp / 'requirements.plist'
        requirements.write_bytes(plistlib.dumps({'arch': [arch], 'os': [info['LSMinimumSystemVersion']]}))
        distribution = temp / 'Distribution.xml'
        run('productbuild', '--synthesize', '--product', requirements, '--package', component, distribution)
        tree = ET.parse(distribution)
        root = tree.getroot()
        title = root.find('title')
        if title is None:
            title = ET.SubElement(root, 'title')
        title.text = 'FlickOff'
        domains = root.find('domains')
        if domains is None:
            domains = ET.SubElement(root, 'domains')
        domains.attrib = {'enable_anywhere': 'false', 'enable_currentUserHome': 'false', 'enable_localSystem': 'true'}
        run('sips', '-s', 'format', 'png', app / 'Contents/Resources/AppIcon.icns', '--out', resources / 'icon.png')
        icon = 'data:image/png;base64,' + base64.b64encode((resources / 'icon.png').read_bytes()).decode('ascii')
        for element, filename in [('welcome', 'welcome.html'), ('conclusion', 'conclusion.html')]:
            text = (ROOT / 'Packaging/Installer' / filename).read_text()
            (resources / filename).write_text(text.replace('@VERSION@', html.escape(version)).replace('@ICON_DATA@', icon))
            ET.SubElement(root, element, {'file': filename, 'mime-type': 'text/html'})
        license_text = '\n\n'.join((ROOT / name).read_text() for name in ('LICENSE', 'NOTICE', 'COMMERCIAL.md'))
        options = root.find('options')
        options.set('customize', 'never')
        ET.indent(tree)
        tree.write(distribution, encoding='utf-8', xml_declaration=True)
        command = ['productbuild', '--distribution', distribution, '--resources', resources,
                   '--package-path', temp]
        if args.sign_identity:
            command += ['--sign', args.sign_identity]
        run(*command, output)
        disk = temp / 'disk'
        installer = disk / 'Install FlickOff.app'
        installer_resources = installer / 'Contents/Resources'
        installer_binary = installer / 'Contents/MacOS/FlickOffInstaller'
        installer_resources.mkdir(parents=True)
        installer_binary.parent.mkdir()
        shutil.copy2(output, installer_resources / 'FlickOff.pkg')
        shutil.copy2(app / 'Contents/Resources/AppIcon.icns', installer_resources / 'AppIcon.icns')
        shutil.copy2(ROOT / 'Packaging/Installer/install.applescript', installer_resources / 'install.applescript')
        (installer_resources / 'license.txt').write_text(license_text)
        (installer / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': bundle_id + '.Installer',
            'CFBundleName': 'FlickOff Installer',
            'CFBundleDisplayName': 'FlickOff Installer',
            'CFBundleExecutable': 'FlickOffInstaller',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': build,
            'CFBundleShortVersionString': version,
            'CFBundleIconFile': 'AppIcon',
            'LSMinimumSystemVersion': info['LSMinimumSystemVersion'],
            'LSRequiresNativeExecution': True,
            'NSHighResolutionCapable': True,
        }))
        run('xcrun', 'clang', '-fobjc-arc', '-arch', arch,
            '-mmacosx-version-min=' + info['LSMinimumSystemVersion'], '-framework', 'Cocoa',
            ROOT / 'Packaging/Installer/InstallerApp.m', '-o', installer_binary)
        signing = ['codesign', '--force', '--sign', args.app_sign_identity or '-']
        if args.app_sign_identity:
            signing += ['--options', 'runtime', '--timestamp']
        run(*signing, installer)
        run('codesign', '--verify', '--deep', '--strict', installer)
        run(installer_binary, '--self-test')
        run('ditto', installer, args.output / 'Install FlickOff.app')
        run('hdiutil', 'create', '-volname', 'FlickOff Installer', '-srcfolder', disk,
            '-fs', 'HFS+', '-format', 'UDZO', image)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    print(f'Installer: {output}')
    print(f'Installer disk image: {image}')
    print(f'SHA256: {checksum}')
    print('Installs in /Applications; upgrades in place; preserves user preferences.')
    if not args.sign_identity:
        print('Beta installer is unsigned and not notarized.')


if __name__ == '__main__':
    main()
