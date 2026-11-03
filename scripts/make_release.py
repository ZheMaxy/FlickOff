#!/usr/bin/env python3
"""Package FlickOff and sign its archive and appcast with the owner's Keychain key."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout


def published_build(feed):
    """The newest build in the feed users read now; Sparkle ignores anything that isn't newer."""
    versions = ET.parse(feed).getroot().iter(f'{{{SPARKLE}}}version')
    return max((int(version.text) for version in versions), default=0)


def release_problems(tag, version, build, notes, published):
    """Mistakes that would ship a release users can't get or can't tell apart."""
    problems = []
    if not re.fullmatch(rf'v{re.escape(version)}(-(alpha|beta|rc)\.[0-9]+)?', tag):
        problems.append(f'Tag {tag} does not match version {version}')
    if not build.isascii() or not build.isdecimal() or int(build) <= published:
        problems.append(f'Build {build} must be higher than the published build {published}')
    if notes is None or not notes.strip():
        problems.append('Pass --notes with a file saying what changed; the update alert shows it')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('build/FlickOff.app'))
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--notes', type=Path, help='Plain-text file saying what changed; the update alert shows it')
    parser.add_argument('--download-prefix')
    parser.add_argument('--key-account', default='io.github.ZheMaxy.FlickOff')
    parser.add_argument('--archive-only', action='store_true', help='Skip the native installer for isolated updater fixtures')
    args = parser.parse_args()
    info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    notes = args.notes.read_text() if args.notes else None
    if args.archive_only:
        notes = 'Updater test fixture.'
    else:
        problems = release_problems(args.tag, version, build, notes, published_build(ROOT / 'appcast.xml'))
        if problems:
            raise SystemExit('\n'.join(problems))
    if run('lipo', '-archs', args.app / 'Contents/MacOS/FlickOff').strip() != 'arm64':
        raise SystemExit('Only native arm64 release archives are allowed')
    run('codesign', '--verify', '--deep', '--strict', args.app)
    signer = Path('.build/artifacts/sparkle/Sparkle/bin/sign_update')
    if not signer.is_file():
        raise SystemExit('Run ./build.sh to resolve the pinned Sparkle tools first')
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f'FlickOff-{version}-arm64.zip'
    if archive.exists():
        raise SystemExit('Output archive already exists; use a new output directory')
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', args.app, archive)
    signed = run(signer, '--account', args.key_account, archive)
    signature = re.search(r'edSignature="([A-Za-z0-9+/=]+)"', signed)
    if not signature:
        raise SystemExit('Signing tool did not return an archive signature')
    run(signer, '--account', args.key_account, '--verify', archive, signature.group(1))
    prefix = args.download_prefix or f'https://github.com/ZheMaxy/FlickOff/releases/download/{args.tag}'
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'FlickOff Updates'
    ET.SubElement(channel, 'link').text = 'https://github.com/ZheMaxy/FlickOff'
    ET.SubElement(channel, 'description').text = 'Signed FlickOff software updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'FlickOff {version} (build {build})'
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = build
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = info['LSMinimumSystemVersion'] + '.0'
    ET.SubElement(item, f'{{{SPARKLE}}}hardwareRequirements').text = 'arm64'
    ET.SubElement(item, 'description', {f'{{{SPARKLE}}}format': 'plain-text'}).text = notes.strip()
    ET.SubElement(item, 'enclosure', {
        'url': prefix.rstrip('/') + '/' + archive.name,
        f'{{{SPARKLE}}}edSignature': signature.group(1),
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    })
    feed = args.output / 'appcast.xml'
    ET.indent(rss)
    ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
    run(signer, '--account', args.key_account, feed)
    run(signer, '--account', args.key_account, '--verify', feed)
    artifacts = [archive]
    if not args.archive_only:
        run(sys.executable, Path(__file__).with_name('make_installer.py'), '--app', args.app, '--output', args.output)
        artifacts.append(args.output / f'FlickOff-{version}-arm64.dmg')
    checksums = ''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in artifacts)
    (args.output / 'SHA256SUMS').write_text(checksums)
    print(f'Signed archive: {archive}')
    print(f'Signed appcast: {feed}')
    for artifact in artifacts[1:]:
        print(f'Native installer: {artifact}')
    print('Archive and feed signatures verified; signing key stayed in Keychain.')


if __name__ == '__main__':
    main()
