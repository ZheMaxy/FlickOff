#!/usr/bin/env python3
"""Check what search engines read on the website, so a later edit can't quietly break it."""
import json
import re
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / 'site'
BASE = 'https://zhemaxy.github.io/FlickOff/'
# Copied into the site when it's deployed.
IMAGES = {'menu.png', 'icon.png', 'favicon.png', 'social-preview.png'}
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta, self.links, self.images, self.anchors, self.ids, self.h1 = {}, {}, [], [], set(), 0
        self.title, self.structured, self.stack = '', [], []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        if tag == 'meta':
            self.meta[attrs.get('name') or attrs.get('property')] = attrs.get('content')
        elif tag == 'link':
            self.links[attrs.get('rel')] = attrs.get('href')
        elif tag == 'img':
            self.images.append(attrs)
        elif tag == 'a':
            self.anchors.append(attrs.get('href'))
        elif tag == 'h1':
            self.h1 += 1
        self.stack.append((tag, attrs))

    def handle_endtag(self, tag):
        if self.stack:
            self.stack.pop()

    def handle_data(self, data):
        if not self.stack:
            return
        tag, attrs = self.stack[-1]
        if tag == 'title':
            self.title += data
        elif tag == 'script' and attrs.get('type') == 'application/ld+json':
            self.structured.append(json.loads(data))


def read(path):
    page = Page()
    page.feed(path.read_text())
    return page


def local_target(url, here):
    """The file a link on the page at `here` leads to, or None for another site."""
    if not url.startswith(BASE):
        return None
    relative = urlparse(url).path[len(urlparse(BASE).path):]
    target = SITE / relative
    return target / 'index.html' if not relative or relative.endswith('/') else target


def main():
    pages = sorted(SITE.rglob('index.html'))
    assert len(pages) >= 3
    listed = {node.text for node in ET.parse(SITE / 'sitemap.xml').getroot().iter('{http://www.sitemaps.org/schemas/sitemap/0.9}loc')}
    canonical = set()
    for path in pages:
        page, name = read(path), path.relative_to(SITE)
        address = BASE + str(path.relative_to(SITE).parent).replace('.', '') + ('/' if path.parent != SITE else '')
        assert 20 <= len(page.title) <= 60, f'{name}: title is {len(page.title)} characters'
        description = page.meta['description']
        assert 70 <= len(description) <= 160, f'{name}: description is {len(description)} characters'
        assert page.links['canonical'] == address, f'{name}: canonical is {page.links["canonical"]}'
        assert page.h1 == 1, f'{name}: has {page.h1} h1 headings'
        assert page.meta['og:title'] == page.title and page.meta['og:url'] == address, name
        assert page.meta['twitter:card'] == 'summary_large_image', name
        assert urlparse(page.meta['og:image']).path.split('/')[-1] in IMAGES, name
        assert page.structured, f'{name}: no structured data'
        canonical.add(address)
        for image in page.images:
            assert 'alt' in image and image.get('width') and image.get('height'), f'{name}: image without alt or size: {image}'
        for href in page.anchors:
            target = urljoin(address, href)
            local = local_target(target, address)
            if local is not None:
                assert local.exists(), f'{name}: {href} leads nowhere'
                fragment = urlparse(target).fragment
                assert not fragment or fragment in read(local).ids, f'{name}: {href} has no target'
    assert canonical == listed, f'sitemap differs from the pages: {canonical ^ listed}'
    print('PASS: every page has its title, description, canonical address, preview tags and working links')

    home = read(SITE / 'index.html').structured[0]['@graph']
    application = next(node for node in home if node['@type'] == 'SoftwareApplication')
    assert 'aggregateRating' not in application and 'review' not in application, 'ratings must be real'
    items = ET.parse(ROOT / 'appcast.xml').getroot().iter('item')
    newest = max(items, key=lambda item: int(item.findtext(f'{SPARKLE}version')))
    version = newest.findtext(f'{SPARKLE}shortVersionString')
    tag = newest.find('enclosure').attrib['url'].split('/')[-2]
    assert application['softwareVersion'] == version, f"the site says {application['softwareVersion']}, the feed {version}"
    assert application['downloadUrl'].endswith(f'/{tag}/FlickOff-{version}-arm64.dmg'), application['downloadUrl']
    text = (SITE / 'index.html').read_text()
    assert set(re.findall(r'releases/download/([^/"]+)/', text)) == {tag}, 'a download link points at another release'
    print('PASS: the home page offers the version the update feed does')

    faq = next(node for node in home if node['@type'] == 'FAQPage')
    visible = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', text.split('</script>')[1]))
    for question in faq['mainEntity']:
        assert question['name'] in visible, question['name']
        assert question['acceptedAnswer']['text'] in visible.replace('&amp;', '&'), question['name']
    print('PASS: structured questions and answers match what the page shows')


if __name__ == '__main__':
    main()
