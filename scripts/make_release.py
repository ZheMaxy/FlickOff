#!/usr/bin/env python3
"""Sign a FlickOff release and its update feed with the owner's Keychain key.

Real releases sign the files CI built and attested; scripts/publish.py runs this with --prebuilt.
"""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = ROOT / 'build/preflight.json'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def sparkle(name):
    return f'{{{SPARKLE}}}{name}'


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout


def published_build(feed):
    """The newest build in the feed users read now; Sparkle ignores anything that isn't newer."""
    versions = ET.parse(feed).getroot().iter(sparkle('version'))
    return max((int(version.text) for version in versions), default=0)


def preflight_commit(result=PREFLIGHT):
    """The commit scripts/preflight.py last passed for, if any."""
    try:
        return json.loads(Path(result).read_text()).get('commit')
    except (OSError, ValueError):
        return None


def release_problems(tag, version, build, notes, published, preflight, commit):
    """Mistakes that would ship a release users can't get, can't tell apart, or that nothing checked."""
    problems = []
    if not re.fullmatch(rf'v{re.escape(version)}(-(alpha|beta|rc)\.[0-9]+)?', tag):
        problems.append(f'Tag {tag} does not match version {version}')
    if not build.isascii() or not build.isdecimal() or int(build) <= published:
        problems.append(f'Build {build} must be higher than the published build {published}')
    if notes is None or not notes.strip():
        problems.append('Pass --notes with a file saying what changed; the update alert shows it')
    if preflight is None or preflight != commit:
        problems.append(f"Run scripts/preflight.py for commit {commit[:7]} first; it covers what hosted CI can't")
    return problems


def kept_items(feed, channel):
    """The newest item of every other channel, so their users aren't left without an update."""
    newest = {}
    for item in ET.parse(feed).getroot().iter('item'):
        other = item.findtext(sparkle('channel'))
        build = int(item.findtext(sparkle('version')))
        if other != channel and (other not in newest or build > newest[other][0]):
            newest[other] = (build, item)
    return [item for _, item in sorted(newest.values(), key=lambda entry: entry[0], reverse=True)]


def make_item(version, build, notes, minimum_system, url, signature, length, channel=None, rollout_hours=None):
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = f'FlickOff {version} (build {build})'
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, sparkle('version')).text = build
    ET.SubElement(item, sparkle('shortVersionString')).text = version
    ET.SubElement(item, sparkle('minimumSystemVersion')).text = minimum_system + '.0'
    ET.SubElement(item, sparkle('hardwareRequirements')).text = 'arm64'
    if channel:
        ET.SubElement(item, sparkle('channel')).text = channel
    if rollout_hours:
        # Sparkle offers it to one of seven groups of users per interval.
        ET.SubElement(item, sparkle('phasedRolloutInterval')).text = str(rollout_hours * 3600)
    ET.SubElement(item, 'description', {sparkle('format'): 'plain-text'}).text = notes.strip()
    ET.SubElement(item, 'enclosure', {
        'url': url, sparkle('edSignature'): signature,
        'length': str(length), 'type': 'application/octet-stream',
    })
    return item


def only_file(directory, pattern):
    found = sorted(directory.rglob(pattern))
    if len(found) != 1:
        raise SystemExit(f'Expected one {pattern} in {directory}, found {len(found)}')
    return found[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/FlickOff.app')
    parser.add_argument('--prebuilt', type=Path, help='Directory with the ZIP and DMG to sign, as CI built them')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--notes', type=Path, help='Plain-text file saying what changed; the update alert shows it')
    parser.add_argument('--channel', choices=['beta'], help="Offer it only to builds that accept this channel; older builds won't see it")
    parser.add_argument('--phased-rollout-hours', type=int, help='Offer it to one of seven groups of users per this many hours')
    parser.add_argument('--download-prefix')
    parser.add_argument('--key-account', default='io.github.ZheMaxy.FlickOff')
    parser.add_argument('--archive-only', action='store_true', help='Skip the release guards and the installer for isolated updater fixtures')
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix='flickoff-release-') as temp:
        app = args.app
        if args.prebuilt:
            prebuilt_archive = only_file(args.prebuilt, 'FlickOff-*-arm64.zip')
            prebuilt_image = only_file(args.prebuilt, 'FlickOff-*-arm64.dmg')
            run('ditto', '-x', '-k', prebuilt_archive, temp)
            app = Path(temp) / 'FlickOff.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
        notes = args.notes.read_text() if args.notes else None
        feed_on_main = ROOT / 'appcast.xml'
        if args.archive_only:
            notes = 'Updater test fixture.'
        else:
            commit = run('git', '-C', ROOT, 'rev-parse', 'HEAD').strip()
            problems = release_problems(args.tag, version, build, notes, published_build(feed_on_main),
                                        preflight_commit(), commit)
            if problems:
                raise SystemExit('\n'.join(problems))
        if run('lipo', '-archs', app / 'Contents/MacOS/FlickOff').strip() != 'arm64':
            raise SystemExit('Only native arm64 release archives are allowed')
        run('codesign', '--verify', '--deep', '--strict', app)
        signer = ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
        if not signer.is_file():
            raise SystemExit('Run ./build.sh to resolve the pinned Sparkle tools first')
        args.output.mkdir(parents=True, exist_ok=True)
        archive = args.output / f'FlickOff-{version}-arm64.zip'
        if archive.exists():
            raise SystemExit('Output archive already exists; use a new output directory')
        if args.prebuilt:
            if prebuilt_archive.name != archive.name:
                raise SystemExit(f'{prebuilt_archive.name} does not match the version inside it, {version}')
            shutil.copy2(prebuilt_archive, archive)
        else:
            run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
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
        channel.append(make_item(version, build, notes, info['LSMinimumSystemVersion'],
                                 prefix.rstrip('/') + '/' + archive.name, signature.group(1), archive.stat().st_size,
                                 args.channel, args.phased_rollout_hours))
        if not args.archive_only:
            channel.extend(kept_items(feed_on_main, args.channel))
        feed = args.output / 'appcast.xml'
        ET.indent(rss)
        ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
        run(signer, '--account', args.key_account, feed)
        run(signer, '--account', args.key_account, '--verify', feed)
        artifacts = [archive]
        if args.prebuilt:
            image = args.output / prebuilt_image.name
            shutil.copy2(prebuilt_image, image)
            artifacts.append(image)
        elif not args.archive_only:
            run(sys.executable, Path(__file__).with_name('make_installer.py'), '--app', app, '--output', args.output)
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
