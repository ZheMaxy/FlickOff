#!/usr/bin/env python3
"""Check the release guards against feed fixtures. Needs no signing key."""
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('make_release', ROOT / 'scripts/make_release.py')
make_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_release)


def main():
    # The real feed carries its signature in a comment after the root element.
    assert make_release.published_build(ROOT / 'appcast.xml') >= 4
    with tempfile.TemporaryDirectory(prefix='flickoff-release-checks-') as temp:
        feed = Path(temp) / 'appcast.xml'
        feed.write_text(f'''<rss xmlns:sparkle="{make_release.SPARKLE}"><channel>
            <item><sparkle:version>7</sparkle:version></item>
            <item><sparkle:version>12</sparkle:version></item>
            </channel></rss><!-- sparkle-signatures: -->''')
        assert make_release.published_build(feed) == 12
        feed.write_text('<rss><channel></channel></rss>')
        assert make_release.published_build(feed) == 0
    print('PASS: the published build is read from the feed')

    def problems(tag='v1.2.0', version='1.2.0', build='5', notes='Fixes.', published=4):
        return make_release.release_problems(tag, version, build, notes, published)

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
    assert len(problems(tag='x', build='1', notes=None)) == 3
    print('PASS: every release says what changed')


if __name__ == '__main__':
    main()
