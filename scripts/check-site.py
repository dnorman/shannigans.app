from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1] / "dist"


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path, self.ids, self.links = path, set(), []
        self.headings = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, (self.path, "duplicate id", attrs["id"])
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.headings += 1
        if tag == "img":
            assert "alt" in attrs, (self.path, "missing alt")
        for key in ("href", "src"):
            if key in attrs:
                self.links.append(attrs[key])


pages = {}
for path in ROOT.rglob("*.html"):
    page = Page(path)
    page.feed(path.read_text())
    assert page.headings == 1, (path, "expected one h1")
    pages[path.resolve()] = page
for path, page in pages.items():
    for link in page.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        target = (ROOT / url.path.lstrip("/") if url.path.startswith("/") else path.parent / unquote(url.path)) if url.path else path
        if target.is_dir():
            target /= "index.html"
        assert target.exists(), (path, "missing target", link)
        if url.fragment:
            assert url.fragment in pages[target.resolve()].ids, (path, "missing anchor", link)
print(f"Validated {len(pages)} pages, local links, anchors, and image descriptions.")
