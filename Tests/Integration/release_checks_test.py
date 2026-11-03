#!/usr/bin/env python3
"""Check the release guards and the feed check against fixtures. Needs no signing key."""
import importlib.util
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f'scripts/{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


make_release = load('make_release')
publish = load('publish')
SPARKLE = make_release.SPARKLE


def feed_text(*items):
    return f'<rss xmlns:sparkle="{SPARKLE}"><channel>' + ''.join(items) + '</channel></rss><!-- sparkle-signatures: -->'


def item(build, channel=None):
    tag = f'<sparkle:channel>{channel}</sparkle:channel>' if channel else ''
    return f'<item><sparkle:version>{build}</sparkle:version>{tag}</item>'


def main():
    # The real feed carries its signature in a comment after the root element.
    assert make_release.published_build(ROOT / 'appcast.xml') >= 4
    with tempfile.TemporaryDirectory(prefix='flickoff-release-checks-') as temp:
        temp = Path(temp)
        feed = temp / 'appcast.xml'
        feed.write_text(feed_text(item(7), item(12)))
        assert make_release.published_build(feed) == 12
        feed.write_text('<rss><channel></channel></rss>')
        assert make_release.published_build(feed) == 0
        print('PASS: the published build is read from the feed')

        def problems(tag='v1.2.0', version='1.2.0', build='5', notes='Fixes.', published=4, preflight='abc', commit='abc'):
            return make_release.release_problems(tag, version, build, notes, published, preflight, commit)

        assert problems() == []
        for tag in ('v1.2.0-beta.3', 'v1.2.0-rc.1', 'v1.2.0-alpha.1'):
            assert problems(tag=tag) == [], tag
        for tag in ('v1.2.1', '1.2.0', 'v1.2.0-beta', 'v1.2.0-beta.x', 'v1x2x0', 'test', ''):
            assert len(problems(tag=tag)) == 1 and 'Tag' in problems(tag=tag)[0], tag
        print('PASS: the tag must match the app version')

        for build in ('4', '3', '0', 'five', '', '٥'):
            assert len(problems(build=build)) == 1 and 'Build' in problems(build=build)[0], build
        print('PASS: a build no newer than the published one is refused')

        for notes in (None, '', ' \n\t'):
            assert len(problems(notes=notes)) == 1 and '--notes' in problems(notes=notes)[0], repr(notes)
        print('PASS: every release says what changed')

        for preflight in (None, 'older'):
            assert len(problems(preflight=preflight)) == 1 and 'preflight' in problems(preflight=preflight)[0]
        assert make_release.preflight_commit(temp / 'missing.json') is None
        (temp / 'broken.json').write_text('{')
        assert make_release.preflight_commit(temp / 'broken.json') is None
        (temp / 'passed.json').write_text('{"commit": "abc"}')
        assert make_release.preflight_commit(temp / 'passed.json') == 'abc'
        assert len(problems(tag='x', build='1', notes=None, preflight=None)) == 4
        print('PASS: a release needs a passing preflight for its own commit')

        feed.write_text(feed_text(item(5), item(6, 'beta'), item(4), item(3, 'beta')))
        def builds(channel):
            return [int(kept.findtext(f'{{{SPARKLE}}}version')) for kept in make_release.kept_items(feed, channel)]
        assert builds(None) == [6]
        assert builds('beta') == [5]
        print('PASS: a release keeps the newest item of the other channel')

        plain = make_release.make_item('1.2.0', '5', 'Fixes.', '13.0', 'https://x/a.zip', 'sig', 10)
        assert plain.find(f'{{{SPARKLE}}}channel') is None and plain.find(f'{{{SPARKLE}}}phasedRolloutInterval') is None
        beta = make_release.make_item('1.2.0', '5', 'Fixes.', '13.0', 'https://x/a.zip', 'sig', 10, 'beta', 24)
        assert beta.findtext(f'{{{SPARKLE}}}channel') == 'beta'
        assert beta.findtext(f'{{{SPARKLE}}}phasedRolloutInterval') == '86400'
        assert plain.find('description').attrib[f'{{{SPARKLE}}}format'] == 'plain-text'
        print('PASS: channels and phased rollout reach the feed only when asked for')

        link = 'https://github.com/ZheMaxy/FlickOff/releases/download/v1.1.0-beta.2/FlickOff-1.1.0-arm64.dmg'
        text = publish.rewrite_links(f'[Download FlickOff-1.1.0-arm64.dmg]({link}) and [all](https://x/releases)', 'v1.2.0-beta.1', '1.2.0')
        assert text == ('[Download FlickOff-1.2.0-arm64.dmg](https://github.com/ZheMaxy/FlickOff/releases/download/'
                        'v1.2.0-beta.1/FlickOff-1.2.0-arm64.dmg) and [all](https://x/releases)')
        cask = publish.rewrite_cask((ROOT / 'Casks/flickoff.rb').read_text(), 'v1.2.0-beta.1', '1.2.0', 'f' * 64)
        assert 'version "1.2.0"' in cask and f'sha256 "{"f" * 64}"' in cask
        assert 'releases/download/v1.2.0-beta.1/FlickOff-#{version}-arm64.zip' in cask
        print('PASS: publishing rewrites the download links and the cask')

        def verify(*arguments):
            command = ['swift', ROOT / 'scripts/verify_feed.swift', *arguments, ROOT / 'Resources/Info.plist']
            return subprocess.run([str(c) for c in command], capture_output=True, text=True, check=False).returncode

        real = (ROOT / 'appcast.xml').read_bytes()
        assert verify(ROOT / 'appcast.xml') == 0
        tampered = temp / 'tampered.xml'
        tampered.write_bytes(real.replace(b'FlickOff Updates', b'FakeOff Updates', 1))
        assert verify(tampered) == 1
        unsigned = temp / 'unsigned.xml'
        unsigned.write_bytes(real.split(b'<!-- sparkle-signatures')[0])
        assert verify(unsigned) == 1
        print('PASS: the feed check accepts the real feed and refuses a changed or unsigned one')


if __name__ == '__main__':
    main()
