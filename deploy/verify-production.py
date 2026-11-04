#!/usr/bin/env python3
"""Read-only HTTP checks for a deployed Evolving Minds instance.

Does not send credentials, change the world, print cookies, or execute admin actions.
Browser behavior is covered separately by e2e/.
"""
import argparse
import json
from html.parser import HTMLParser
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-url", default="https://elixir.micutu.com")
args = parser.parse_args()
base = args.base_url.rstrip("/")
url = urllib.parse.urlsplit(base)
if url.scheme != "https" or not url.netloc or url.username or url.password or url.query or url.fragment or url.path not in ["", "/"]:
    parser.error("Use an HTTPS origin without credentials, query parameters or fragments")

class Metadata(HTMLParser):
    def __init__(self):
        super().__init__()
        self.canonical = None
        self.metas = {}

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "link" and values.get("rel") == "canonical":
            self.canonical = values.get("href")
        if tag == "meta":
            self.metas[values.get("name") or values.get("property")] = values.get("content")


def request(path):
    req = urllib.request.Request(base + path, headers={"User-Agent": "Mozilla/5.0"})
    try:
        response = urllib.request.urlopen(req, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read(1_000_001)


def require(condition, message):
    if not condition:
        raise SystemExit("FAILED: " + message)

for path in ["/", "/tree", "/lab"]:
    status, headers, body = request(path)
    require(status == 200, f"{path} status must be 200 (got {status})")
    require(len(body) <= 1_000_000, f"{path} exceeded the verification response limit")
    meta = Metadata()
    meta.feed(body.decode("utf-8"))
    require(meta.canonical == base + path, f"{path} has an unexpected canonical URL")
    require(meta.metas.get("description"), f"{path} has no search description")
    require(meta.metas.get("og:image"), f"{path} has no social image")
    require("frame-ancestors 'none'" in headers.get("Content-Security-Policy", ""), "Frame protection missing")
    require(headers.get("Strict-Transport-Security"), "HSTS missing")
    cookies = headers.get_all("Set-Cookie", [])
    session = next((value.lower() for value in cookies if value.startswith("_evolving_minds_key=")), "")
    require(all(flag in session for flag in ["secure", "httponly", "samesite=lax"]), "Session cookie flags missing")
    print(f"OK {path}: HTTPS, canonical, metadata, headers, cookie flags")

status, _, body = request("/healthz")
require(status == 200 and json.loads(body) == {"status": "ok"}, "Readiness failed")
print("OK /healthz: simulation and publisher ready")
status, _, body = request("/robots.txt")
require(status == 200 and b"Disallow: /admin/" in body and (base + "/sitemap.xml").encode() in body, "Robots directives missing")
status, _, body = request("/sitemap.xml")
require(status == 200, "Sitemap unavailable")
locations = {element.text for element in ET.fromstring(body).iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc")}
require(locations == {base + path for path in ["/", "/tree", "/lab"]}, "Sitemap does not match canonical product pages")
print("OK robots and sitemap: all three product pages")
for path in ["/admin/world", "/admin/dashboard", "/.env", "/.git/config", "/data/world.snapshot"]:
    status, _, _ = request(path)
    require(status in [400, 401, 403, 404], f"Protected path {path} returned {status}")
    print(f"OK protected path {path}: {status}")
print("Production HTTP checks passed. No credentials or simulation mutations were sent.")
