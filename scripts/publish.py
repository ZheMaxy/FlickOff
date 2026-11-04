#!/usr/bin/env python3
"""Publish a release in two steps, so it can be tried out before anyone is offered it.

upload  checks the files CI built and attested, signs them with the Keychain key and uploads
        them as a public release. Nobody is offered them yet.
feed    publishes the signed feed, the Homebrew cask and the download links on main and on the website.
        This is the step that reaches users.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'ZheMaxy/FlickOff'
FEED_URL = f'https://raw.githubusercontent.com/{REPOSITORY}/main/appcast.xml'
LINKS_TO_THE_RELEASE = ('README.md', 'docs/INSTALL.md', 'site/index.html')
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


def run(*args):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()


def rewrite_links(text, tag, version):
    """Point the download links in a document at this release."""
    text = re.sub(r'releases/download/[^/\s]+/FlickOff-[0-9.]+-arm64\.dmg',
                  f'releases/download/{tag}/FlickOff-{version}-arm64.dmg', text)
    text = re.sub(r'"softwareVersion": "[^"]+"', f'"softwareVersion": "{version}"', text)
    return re.sub(r'\[Download FlickOff-[0-9.]+-arm64\.dmg\]', f'[Download FlickOff-{version}-arm64.dmg]', text)


def rewrite_cask(text, tag, version, sha256):
    text = re.sub(r'version "[^"]+"', f'version "{version}"', text, count=1)
    text = re.sub(r'sha256 "[^"]+"', f'sha256 "{sha256}"', text, count=1)
    return re.sub(r'releases/download/[^/]+/', f'releases/download/{tag}/', text, count=1)


def newest_item(feed):
    def build(item):
        return int(item.findtext(f'{{{SPARKLE}}}version'))
    item = max(ET.parse(feed).getroot().iter('item'), key=build)
    url = item.find('enclosure').attrib['url']
    return build(item), item.findtext(f'{{{SPARKLE}}}shortVersionString'), url.split('/')[-2], url.split('/')[-1]


def require_published_head():
    """Releases and feeds describe main as everyone can see it."""
    if run('git', 'status', '--porcelain'):
        raise SystemExit('Commit your changes first')
    run('git', 'fetch', 'origin', 'main')
    if run('git', 'rev-parse', 'HEAD') != run('git', 'rev-parse', 'origin/main'):
        raise SystemExit('HEAD is not origin/main; push first')


def upload(args):
    require_published_head()
    commit = run('git', 'rev-parse', 'HEAD')
    build_run = json.loads(run('gh', 'run', 'view', args.run, '-R', REPOSITORY, '--json', 'headSha,conclusion,workflowName'))
    if build_run['workflowName'] != 'Release build' or build_run['conclusion'] != 'success':
        raise SystemExit(f'Run {args.run} is not a successful Release build')
    if build_run['headSha'] != commit:
        raise SystemExit(f"Run {args.run} built {build_run['headSha'][:7]}, not {commit[:7]}")
    built = args.output / 'ci'
    run('gh', 'run', 'download', args.run, '-R', REPOSITORY, '--name', 'release-files', '--dir', built.resolve())
    for file in sorted(built.iterdir()):
        run('gh', 'attestation', 'verify', file.resolve(), '--repo', REPOSITORY,
            '--signer-workflow', f'{REPOSITORY}/.github/workflows/release.yml')
        print(f'Attested by this repository\'s CI: {file.name}', flush=True)
    command = [sys.executable, 'scripts/make_release.py', '--prebuilt', built.resolve(), '--tag', args.tag,
               '--notes', args.notes.resolve(), '--output', args.output.resolve()]
    if args.channel:
        command += ['--channel', args.channel]
    if args.phased_rollout_hours:
        command += ['--phased-rollout-hours', args.phased_rollout_hours]
    print(run(*command), flush=True)
    assets = sorted(path for path in args.output.iterdir() if path.is_file())
    release = ['gh', 'release', 'create', args.tag, '-R', REPOSITORY, '--target', commit, '--title', args.title,
               '--notes-file', args.body.resolve(), *[path.resolve() for path in assets], ROOT / 'Packaging/FIRST-OPEN.txt']
    if not args.stable:
        release.append('--prerelease')
    print(run(*release), flush=True)
    for path in assets:
        with urllib.request.urlopen(f'https://github.com/{REPOSITORY}/releases/download/{args.tag}/{path.name}') as response:
            if hashlib.sha256(response.read()).hexdigest() != hashlib.sha256(path.read_bytes()).hexdigest():
                raise SystemExit(f'The published {path.name} differs from the signed file')
    print(run('swift', 'scripts/verify_feed.swift', args.output.resolve() / 'appcast.xml', 'Resources/Info.plist', '--archives'), flush=True)
    print(f'\nUploaded {args.tag}; nobody is offered it yet. Try it, then run: scripts/publish.py feed --output {args.output}')


def feed(args):
    require_published_head()
    signed = args.output / 'appcast.xml'
    build, version, tag, archive = newest_item(signed)
    sha256 = hashlib.sha256((args.output / archive).read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='flickoff-feed-') as temp:
        previous = Path(temp) / 'previous.xml'
        shutil.copyfile(ROOT / 'appcast.xml', previous)
        print(run('swift', 'scripts/verify_feed.swift', signed.resolve(), 'Resources/Info.plist', '--archives', '--newer-than', previous), flush=True)
    shutil.copyfile(signed, ROOT / 'appcast.xml')
    for name in LINKS_TO_THE_RELEASE:
        path = ROOT / name
        path.write_text(rewrite_links(path.read_text(), tag, version))
    cask = ROOT / 'Casks/flickoff.rb'
    cask.write_text(rewrite_cask(cask.read_text(), tag, version, sha256))
    run('git', 'add', 'appcast.xml', *LINKS_TO_THE_RELEASE, 'Casks/flickoff.rb')
    run('git', 'commit', '-m', f'Publish signed update feed for build {build}')
    run('git', 'push', 'origin', 'HEAD:main')
    # The raw content CDN can lag a push by a few minutes.
    for _ in range(20):
        with urllib.request.urlopen(FEED_URL) as response:
            if response.read() == signed.read_bytes():
                print(f'Users are now offered build {build}.')
                return
        time.sleep(30)
    raise SystemExit(f'The push went through, but {FEED_URL} still serves something else; check it again shortly')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest='step', required=True)
    first = steps.add_parser('upload', help='Check, sign and upload what CI built')
    first.add_argument('--run', required=True, help='ID of the Release build workflow run')
    first.add_argument('--tag', required=True)
    first.add_argument('--title', required=True, help='Title of the release page')
    first.add_argument('--notes', type=Path, required=True, help='Plain text for the update alert')
    first.add_argument('--body', type=Path, required=True, help='Markdown for the release page')
    first.add_argument('--output', type=Path, required=True, help='A new directory')
    first.add_argument('--stable', action='store_true', help='Not a prerelease')
    first.add_argument('--channel', choices=['beta'])
    first.add_argument('--phased-rollout-hours', type=int)
    first.set_defaults(action=upload)
    second = steps.add_parser('feed', help='Offer the uploaded release to users')
    second.add_argument('--output', type=Path, required=True, help='The directory the upload step used')
    second.set_defaults(action=feed)
    args = parser.parse_args()
    args.action(args)


if __name__ == '__main__':
    main()
