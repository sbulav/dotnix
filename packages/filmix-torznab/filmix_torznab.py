#!/usr/bin/env python3
"""Filmix -> Torznab bridge (issue #39).

Filmix (filmix.tech, DLE engine) hides .torrent files one hop behind
search: search returns *posts* (films/series), while each post's
/download/{post_id} page lists several quality variants, each with a
scene-style filename and a /download-file/{file_id} .torrent link.
Cardigann cannot expand one search row into many releases, so this
bridge does: every quality variant becomes its own Torznab item titled
with the real scene filename -- Radarr/Sonarr parse quality natively.

Endpoints:
  GET /api?t=caps                      Torznab capabilities
  GET /api?t=search|movie|tvsearch&q=  search (q required, else empty feed)
  GET /dl/{file_id}.torrent            proxy the .torrent grab (needs auth)
  GET /health                          liveness

Auth: Filmix DLE session cookies, passed verbatim via FILMIX_COOKIE
(e.g. "dle_user_id=123; dle_password=abcdef..."). These are the
long-lived "remember me" cookies; grab them from a logged-in browser.

Environment:
  FILMIX_COOKIE     required
  FILMIX_URL        default https://filmix.tech
  FILMIX_BIND       default 127.0.0.1
  FILMIX_PORT       default 9117
  FILMIX_MAX_POSTS  download pages fetched per query, default 5
  FILMIX_SWARM      1 to scrape real seeder counts, 0 to skip; default 1
  FILMIX_SWARM_MAX  releases enriched per query, default 25
  FILMIX_SWARM_TTL  swarm-count cache seconds, default 1800

Swarm counts: filmix exposes none, and a large part of its catalogue is
re-hosted .torrent files whose trackers died years ago. Reporting a flat
1/1 (as this bridge used to) makes every release look equally alive, so
the *arrs' minimum-seeders reject never fires and a dead release outranks
nothing. Instead we fetch the .torrent, take its infohash, and scrape its
trackers (BEP 15 over UDP, BEP 48 over HTTP) for the real numbers. A
release nothing answers for is reported as 0 seeders, which is what lets
Radarr/Sonarr throw it away on their own.
"""

from __future__ import annotations

import hashlib
import html as htmlmod
import logging
import os
import random
import re
import socket
import struct
import sys
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import requests
from bs4 import BeautifulSoup

log = logging.getLogger("filmix-torznab")

TORZNAB_NS = "http://torznab.com/schemas/2015/feed"
CAT_MOVIES = "2000"
CAT_TV = "5000"
# DLE post-URL section -> Torznab category. /seria/ and /multserials/ are
# series; everything else on filmix is film-shaped.
TV_SECTIONS = ("/seria/", "/multserials/")

RU_MONTHS = {
    "янв": 1, "фев": 2, "мар": 3, "апр": 4, "май": 5, "мая": 5,
    "июн": 6, "июл": 7, "авг": 8, "сен": 9, "окт": 10, "ноя": 11, "дек": 12,
}

SIZE_UNITS = {"KB": 1 << 10, "MB": 1 << 20, "GB": 1 << 30, "TB": 1 << 40}

CACHE_TTL = 600  # seconds; be polite to filmix
# A .torrent is immutable, so its infohash and tracker list never need
# refetching — only the swarm counts scraped from those trackers do.
BLOB_TTL = 86400
_cache: dict[str, tuple[float, object]] = {}


def cached(key: str, producer, ttl: float = CACHE_TTL):
    now = time.monotonic()
    hit = _cache.get(key)
    if hit and now - hit[0] < ttl:
        return hit[1]
    value = producer()
    _cache[key] = (now, value)
    return value


class Config:
    def __init__(self) -> None:
        cookie = os.environ.get("FILMIX_COOKIE")
        if not cookie:
            log.error("FILMIX_COOKIE is not set (dle_user_id=..; dle_password=..)")
            sys.exit(1)
        self.cookie = cookie
        self.base_url = os.environ.get("FILMIX_URL", "https://filmix.tech").rstrip("/")
        self.bind = os.environ.get("FILMIX_BIND", "127.0.0.1")
        self.port = int(os.environ.get("FILMIX_PORT", "9117"))
        self.max_posts = int(os.environ.get("FILMIX_MAX_POSTS", "5"))
        self.swarm = os.environ.get("FILMIX_SWARM", "1") != "0"
        self.swarm_max = int(os.environ.get("FILMIX_SWARM_MAX", "25"))
        self.swarm_ttl = float(os.environ.get("FILMIX_SWARM_TTL", "1800"))


CFG: Config


def http_session() -> requests.Session:
    s = requests.Session()
    s.headers.update(
        {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0",
            "Cookie": CFG.cookie,
            "Accept-Language": "ru,en;q=0.5",
        }
    )
    return s


SESSION: requests.Session


def looks_logged_out(text: str) -> bool:
    # Only the login form is a reliable marker: a PRO+ session still
    # renders "is_user_pro: 0" (the flags are per-tier, not cumulative).
    return 'id="loginForm"' in text


# --- filmix parsing ---------------------------------------------------------


def parse_size(text: str) -> int:
    # Strict number (no leading dot: "DD5.1.46 GB" must not yield ".1.46")
    # and take the last match — the size annotation trails the filename.
    matches = re.findall(r"(\d+(?:\.\d+)?)\s*([KMGT]B)\b", text, re.I)
    if not matches:
        return 0
    value, unit = matches[-1]
    return int(float(value) * SIZE_UNITS[unit.upper()])


def parse_ru_date(text: str) -> datetime:
    now = datetime.now(timezone.utc)
    text = text.strip().lower()
    if text.startswith("сегодня"):
        return now
    if text.startswith("вчера"):
        return now - timedelta(days=1)
    m = re.search(r"(\d{1,2})\s+([а-я]{3})[а-я]*\.?\s+(\d{4})", text)
    if m and m.group(2) in RU_MONTHS:
        return datetime(
            int(m.group(3)), RU_MONTHS[m.group(2)], int(m.group(1)), tzinfo=timezone.utc
        )
    return now


def latest_posts(section: str) -> list[dict]:
    """Recent posts with a chance of having torrents — serves Prowlarr's
    RSS sync and the app validation tests, all of which query with an
    empty q. Empirically the sources differ per kind: the movie catalog
    page lists movies old enough to have files, while for series the
    criteria-only advanced search (empty story + serials filter, date
    sort) surfaces recently *updated* shows — series catalog pages list
    newly published posts whose torrents don't exist yet."""

    def fetch_film() -> list[dict]:
        r = SESSION.get(f"{CFG.base_url}/film/", timeout=30)
        r.raise_for_status()
        r.encoding = r.encoding or "windows-1251"
        return parse_search_fragment(r.text)

    def fetch_seria() -> list[dict]:
        r = SESSION.post(
            f"{CFG.base_url}/engine/ajax/sphinx_search.php",
            data={
                "scf": "fx",
                "story": "",
                "search_start": "0",
                "do": "search",
                "subaction": "search",
                "serials": "on",
                "sort_date": "desc",
            },
            headers={"X-Requested-With": "XMLHttpRequest"},
            timeout=30,
        )
        r.raise_for_status()
        r.encoding = r.encoding or "windows-1251"
        return parse_search_fragment(r.text)

    fetch = fetch_seria if section == "seria" else fetch_film
    return cached(f"latest:{section}", fetch)


def search_posts(query: str) -> list[dict]:
    """POST the DLE sphinx search, return [{id, title, year, category}]."""

    def fetch() -> list[dict]:
        r = SESSION.post(
            f"{CFG.base_url}/engine/ajax/sphinx_search.php",
            data={
                "scf": "fx",
                "story": query,
                "search_start": "0",
                "do": "search",
                "subaction": "search",
            },
            headers={"X-Requested-With": "XMLHttpRequest"},
            timeout=30,
        )
        r.raise_for_status()
        r.encoding = r.encoding or "windows-1251"
        return parse_search_fragment(r.text)

    return cached(f"search:{query}", fetch)


def parse_search_fragment(fragment: str) -> list[dict]:
    soup = BeautifulSoup(fragment, "html.parser")
    posts = []
    for card in soup.select("article.shortstory"):
        post_id = card.get("data-id")
        if not post_id:
            continue
        name_el = card.select_one("h2.name")
        title = name_el.get_text(strip=True) if name_el else ""
        link_el = card.select_one("h2.name a[href]") or card.select_one("a.watch[href]")
        href = link_el["href"] if link_el else ""
        category = CAT_TV if any(s in href for s in TV_SECTIONS) else CAT_MOVIES
        year = ""
        poster = card.select_one("img.poster[alt]")
        if poster:
            m = re.search(r"\b((?:19|20)\d\d)\b", poster["alt"])
            if m:
                year = m.group(1)
        posts.append({"id": post_id, "title": title, "year": year, "category": category})
    return posts


def fetch_files(post: dict) -> list[dict]:
    """Fetch /download/{post_id}, return one dict per quality variant."""

    def fetch() -> list[dict]:
        r = SESSION.get(f"{CFG.base_url}/download/{post['id']}", timeout=30)
        r.raise_for_status()
        r.encoding = r.encoding or "windows-1251"
        if looks_logged_out(r.text):
            log.warning("download page for post %s looks logged out; cookie expired?", post["id"])
            return []
        return parse_download_page(r.text, post)

    return cached(f"files:{post['id']}", fetch)


def parse_download_page(page: str, post: dict) -> list[dict]:
    """Movie and series download pages use different templates: movies
    render article.item blocks, series render div.series rows grouped by
    translation/season. Parse both; a page only ever contains one kind."""
    soup = BeautifulSoup(page, "html.parser")
    files = parse_movie_items(soup, post)
    seen = {f["file_id"] for f in files}
    files += [f for f in parse_series_items(soup, post) if f["file_id"] not in seen]
    return files


def parse_movie_items(soup: BeautifulSoup, post: dict) -> list[dict]:
    files = []
    for item in soup.select("article.item"):
        onclick = ""
        dl = item.select_one("footer .download[onclick]")
        if dl:
            onclick = dl["onclick"]
        m = re.search(r"download-file/(\d+)", onclick)
        if not m:
            continue
        file_id = m.group(1)

        names, size = [], 0
        for fi in item.select(".file-item"):
            text = fi.get_text(strip=True)
            size += parse_size(text)
            names.append(
                re.sub(r"\s*\(?\d+(?:\.\d+)?\s*[KMGT]B\)?\s*$", "", text, flags=re.I)
            )

        title = release_title(names, item, post)
        date_el = item.select_one("header .date")
        files.append(
            {
                "file_id": file_id,
                "title": title,
                "size": size,
                "date": parse_ru_date(date_el.get_text() if date_el else ""),
                "category": post["category"],
            }
        )
    return files


def parse_series_items(soup: BeautifulSoup, post: dict) -> list[dict]:
    """div.series rows: one row per torrent (an episode range in one
    translation/quality). origin-name is "Folder/First.File.ext" for
    packs — the folder part is the real season-pack release name."""
    files = []
    for el in soup.select("div.series"):
        link = el.select_one("a.download[href]")
        title_el = el.select_one(".series-title[data-id]")
        m = re.search(r"download-file/(\d+)", link["href"]) if link else None
        file_id = m.group(1) if m else (title_el["data-id"] if title_el else None)
        if not file_id:
            continue

        name_el = el.select_one(".origin-name")
        raw = name_el.get_text(strip=True) if name_el else ""
        if "/" in raw:
            title = raw.split("/")[0]
        elif raw:
            title = re.sub(r"\.\w{2,4}$", "", raw)
        else:
            title = " ".join(x for x in [post["title"], post["year"]] if x)

        size_el = el.select_one(".size-series")
        # Season blocks carry the date in a sibling .date-files header.
        date_el = el.find_previous(class_="date-files")
        files.append(
            {
                "file_id": file_id,
                "title": title,
                "size": parse_size(size_el.get_text() if size_el else ""),
                "date": parse_ru_date(date_el.get_text() if date_el else ""),
                "category": post["category"],
            }
        )
    return files


def release_title(names: list[str], item, post: dict) -> str:
    """Scene filename when the variant is a single file; otherwise a
    synthesized season-pack name from the first file."""
    if len(names) == 1:
        return re.sub(r"\.\w{2,4}$", "", names[0])
    if names:
        # Multi-file variant (season pack): drop the episode marker so
        # Sonarr parses it as a full-season release.
        base = re.sub(r"\.\w{2,4}$", "", names[0])
        return re.sub(r"(?i)(S\d{1,2})E\d{1,3}", r"\1", base)
    quality_el = item.select_one(".item-content b")
    quality = quality_el.get_text(strip=True) if quality_el else ""
    return " ".join(x for x in [post["title"], post["year"], quality] if x)


# --- swarm stats ------------------------------------------------------------

# Trackers that can never answer a scrape: LAN-only retrackers, and
# private trackers whose scrape is passkey-gated (the announce URL does
# carry a passkey, but scraping with someone else's is pointless noise).
SKIP_TRACKER_HOSTS = ("retracker.local", "localhost", "127.0.0.1")
SCRAPE_TIMEOUT = 4.0
SCRAPE_MAX_TRACKERS = 8
UDP_PROTOCOL_ID = 0x41727101980


def bdecode(blob: bytes, i: int = 0):
    """Minimal bencode reader. Returns (value, next_index); dicts carry
    the byte span of their "info" value under the __info_span__ key so
    the infohash can be taken over the exact original bytes (re-encoding
    is not guaranteed to round-trip)."""
    head = blob[i : i + 1]
    if head == b"i":
        end = blob.index(b"e", i)
        return int(blob[i + 1 : end]), end + 1
    if head == b"l":
        i += 1
        items = []
        while blob[i : i + 1] != b"e":
            value, i = bdecode(blob, i)
            items.append(value)
        return items, i + 1
    if head == b"d":
        i += 1
        out: dict = {}
        while blob[i : i + 1] != b"e":
            key, i = bdecode(blob, i)
            start = i
            value, i = bdecode(blob, i)
            out[key] = value
            if key == b"info":
                out["__info_span__"] = (start, i)
        return out, i + 1
    sep = blob.index(b":", i)
    length = int(blob[i:sep])
    return blob[sep + 1 : sep + 1 + length], sep + 1 + length


def torrent_meta(blob: bytes) -> tuple[bytes, list[str]]:
    """(infohash, tracker urls) from raw .torrent bytes."""
    meta, _ = bdecode(blob)
    span = meta.get("__info_span__")
    if not span:
        raise ValueError("torrent has no info dict")
    infohash = hashlib.sha1(blob[span[0] : span[1]]).digest()

    urls: list[str] = []
    announce = meta.get(b"announce")
    if announce:
        urls.append(announce.decode("utf-8", "replace"))
    for tier in meta.get(b"announce-list") or []:
        for url in tier:
            if isinstance(url, bytes):
                urls.append(url.decode("utf-8", "replace"))

    seen, ordered = set(), []
    for url in urls:
        host = urlparse(url).hostname or ""
        if host in SKIP_TRACKER_HOSTS or url in seen:
            continue
        seen.add(url)
        ordered.append(url)
    return infohash, ordered


def udp_scrape(host: str, port: int, infohash: bytes) -> tuple[int, int] | None:
    """BEP 15 connect + scrape. Returns (seeders, leechers)."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(SCRAPE_TIMEOUT)
    try:
        tid = random.getrandbits(31)
        sock.sendto(struct.pack(">QII", UDP_PROTOCOL_ID, 0, tid), (host, port))
        reply = sock.recv(64)
        action, rtid, conn = struct.unpack(">IIQ", reply[:16])
        if action != 0 or rtid != tid:
            return None

        tid = random.getrandbits(31)
        sock.sendto(struct.pack(">QII", conn, 2, tid) + infohash, (host, port))
        reply = sock.recv(256)
        action, rtid = struct.unpack(">II", reply[:8])
        if action != 2 or rtid != tid or len(reply) < 20:
            return None
        seeders, _completed, leechers = struct.unpack(">III", reply[8:20])
        return seeders, leechers
    finally:
        sock.close()


def http_scrape(url: str, infohash: bytes) -> tuple[int, int] | None:
    """BEP 48: swap the /announce path segment for /scrape."""
    if "/announce" not in url:
        return None
    scrape_url = url.replace("/announce", "/scrape", 1)
    # trust_env=False: tracker traffic must go direct, never through the
    # SOCKS proxy filmix itself may be reached over.
    with requests.Session() as s:
        s.trust_env = False
        r = s.get(
            scrape_url,
            params={"info_hash": infohash},
            timeout=SCRAPE_TIMEOUT,
            headers={"User-Agent": "filmix-torznab/0.2"},
        )
    if r.status_code != 200 or not r.content.startswith(b"d"):
        return None
    body, _ = bdecode(r.content)
    entry = (body.get(b"files") or {}).get(infohash)
    if not entry:
        return None
    return int(entry.get(b"complete", 0)), int(entry.get(b"incomplete", 0))


def scrape_tracker(url: str, infohash: bytes) -> tuple[int, int] | None:
    parts = urlparse(url)
    if not parts.hostname:
        return None
    try:
        if parts.scheme == "udp":
            return udp_scrape(parts.hostname, parts.port or 80, infohash)
        if parts.scheme in ("http", "https"):
            return http_scrape(url, infohash)
    except (OSError, ValueError, struct.error, requests.RequestException) as exc:
        log.debug("scrape %s failed: %s", url, exc)
    return None


def torrent_blob(file_id: str) -> bytes:
    """The .torrent bytes, cached — search-time swarm checks and the
    /dl/ grab that follows would otherwise fetch each file twice."""

    def fetch() -> bytes:
        r = SESSION.get(f"{CFG.base_url}/download-file/{file_id}", timeout=60)
        r.raise_for_status()
        if not r.content.startswith(b"d"):
            raise ValueError("not a torrent (cookie expired?)")
        return r.content

    return cached(f"blob:{file_id}", fetch, ttl=BLOB_TTL)


def swarm_stats(file_id: str) -> tuple[int, int]:
    """(seeders, leechers), best across the torrent's trackers. Nothing
    reachable means nothing is seeding it *from here*, which is the only
    question the *arrs actually care about — so that reports as zero."""

    def fetch() -> tuple[int, int]:
        infohash, trackers = torrent_meta(torrent_blob(file_id))
        if not trackers:
            return 0, 0
        best = (0, 0)
        targets = trackers[:SCRAPE_MAX_TRACKERS]
        with ThreadPoolExecutor(max_workers=min(8, len(targets))) as pool:
            for result in pool.map(lambda u: scrape_tracker(u, infohash), targets):
                if result and result[0] >= best[0]:
                    best = result
        return best

    try:
        return cached(f"swarm:{file_id}", fetch, ttl=CFG.swarm_ttl)
    except (requests.RequestException, ValueError, IndexError) as exc:
        log.warning("swarm lookup failed for %s: %s", file_id, exc)
        return 0, 0


def enrich_swarm(items: list[dict]) -> None:
    """Attach real seeder/leecher counts in place."""
    if not CFG.swarm:
        return
    targets = items[: CFG.swarm_max]
    if not targets:
        return
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=8) as pool:
        for it, (seeders, leechers) in zip(
            targets, pool.map(lambda i: swarm_stats(i["file_id"]), targets)
        ):
            it["seeders"] = seeders
            it["leechers"] = leechers
    alive = sum(1 for i in targets if i.get("seeders"))
    log.info(
        "swarm: %d/%d releases have seeders (%.1fs)",
        alive,
        len(targets),
        time.monotonic() - started,
    )


# --- torznab xml ------------------------------------------------------------


def caps_xml() -> bytes:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<caps>
  <server title="Filmix Torznab" />
  <limits max="100" default="50" />
  <searching>
    <search available="yes" supportedParams="q" />
    <movie-search available="yes" supportedParams="q" />
    <tv-search available="yes" supportedParams="q" />
  </searching>
  <categories>
    <category id="{CAT_MOVIES}" name="Movies">
      <subcat id="2030" name="Movies/SD" />
      <subcat id="2040" name="Movies/HD" />
      <subcat id="2045" name="Movies/UHD" />
    </category>
    <category id="{CAT_TV}" name="TV">
      <subcat id="5030" name="TV/SD" />
      <subcat id="5040" name="TV/HD" />
      <subcat id="5045" name="TV/UHD" />
    </category>
  </categories>
</caps>
""".encode()


def quality_subcat(title: str, bucket: str) -> str:
    """Map a release title to the newznab quality subcategory (x030 SD /
    x040 HD / x045 UHD) — Sonarr/Radarr filter releases by these."""
    t = title.lower()
    if re.search(r"2160|4k|uhd", t):
        return str(int(bucket) + 45)
    if re.search(r"1080|720", t):
        return str(int(bucket) + 40)
    return str(int(bucket) + 30)


def results_xml(items: list[dict], host: str) -> bytes:
    ET.register_namespace("torznab", TORZNAB_NS)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Filmix Torznab"

    for it in items:
        item = ET.SubElement(channel, "item")
        url = f"http://{host}/dl/{it['file_id']}.torrent"
        ET.SubElement(item, "title").text = it["title"]
        ET.SubElement(item, "guid").text = url
        ET.SubElement(item, "link").text = url
        ET.SubElement(item, "size").text = str(it["size"])
        # Prowlarr's TorznabRssParser NREs without the standard enclosure.
        ET.SubElement(
            item,
            "enclosure",
            {
                "url": url,
                "length": str(it["size"]),
                "type": "application/x-bittorrent",
            },
        )
        ET.SubElement(item, "pubDate").text = it["date"].strftime(
            "%a, %d %b %Y %H:%M:%S +0000"
        )
        # Scraped from the torrent's own trackers (see swarm_stats); a
        # release we could not find a seeder for is reported as dead so
        # the *arrs' minimum-seeders reject can do its job. "peers" is
        # the Torznab total — Prowlarr derives leechers as peers-seeders.
        seeders = int(it.get("seeders", 0))
        leechers = int(it.get("leechers", 0))
        for name, value in [
            ("category", it["category"]),
            ("category", quality_subcat(it["title"], it["category"])),
            ("seeders", str(seeders)),
            ("peers", str(seeders + leechers)),
            ("downloadvolumefactor", "1"),
            ("uploadvolumefactor", "1"),
        ]:
            ET.SubElement(
                item, f"{{{TORZNAB_NS}}}attr", {"name": name, "value": value}
            )

    return b'<?xml version="1.0" encoding="UTF-8"?>' + ET.tostring(rss)


def error_xml(code: int, description: str) -> bytes:
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>'
        f'<error code="{code}" description="{htmlmod.escape(description)}" />'
    ).encode()


# --- http -------------------------------------------------------------------


def handle_search(params: dict, host: str) -> bytes:
    query = (params.get("q") or [""])[0].strip()
    # Radarr may append a year to q; filmix search chokes on it.
    query = re.sub(r"\b(19|20)\d\d\b", "", query).strip()

    # Apps query with subcategories (Sonarr defaults to 5030,5040); we
    # only track the top-level buckets, so normalize 5xxx -> 5000 etc.
    cats = (params.get("cat") or [""])[0]
    wanted = set()
    for c in cats.split(","):
        if c.strip().isdigit():
            wanted.add(str(int(c) // 1000 * 1000))

    t = (params.get("t") or [""])[0]
    if t == "tvsearch":
        sections = ["seria"]
    elif t == "movie":
        sections = ["film"]
    else:
        # Generic search: Sonarr *validates* with t=search, so the empty
        # feed must cover both kinds (narrow by cat filter when present).
        sections = []
        if not wanted or CAT_MOVIES in wanted:
            sections.append("film")
        if not wanted or CAT_TV in wanted:
            sections.append("seria")
    if query:
        posts = search_posts(query)[: CFG.max_posts]
        items = expand_posts(posts)
    else:
        # Fresh posts often lack torrent files (they arrive days after
        # publication) — scan in batches until something real shows up:
        # Sonarr and Radarr refuse an indexer whose test feed is empty.
        posts = [p for s in sections for p in latest_posts(s)]
        items = []
        for i in range(0, min(len(posts), 32), 8):
            items.extend(expand_posts(posts[i : i + 8]))
            if len(items) >= 5:
                break
    if wanted:
        items = [i for i in items if i["category"] in wanted]
    log.info("q=%r t=%s -> %d posts, %d releases", query, t, len(posts), len(items))
    enrich_swarm(items)
    return results_xml(items, host)


def expand_posts(posts: list[dict]) -> list[dict]:
    items: list[dict] = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for files in pool.map(fetch_files, posts):
            items.extend(files)
    return items


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # route through logging
        log.debug("%s " + fmt, self.address_string(), *args)

    def send_body(self, code: int, content_type: str, body: bytes) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        try:
            self.route()
        except requests.RequestException as exc:
            log.error("upstream error: %s", exc)
            self.send_body(502, "application/xml", error_xml(900, str(exc)))
        except Exception:
            log.exception("unhandled error for %s", self.path)
            self.send_body(500, "application/xml", error_xml(900, "internal error"))

    def route(self) -> None:
        url = urlparse(self.path)
        host = self.headers.get("Host", f"{CFG.bind}:{CFG.port}")

        if url.path == "/health":
            self.send_body(200, "text/plain", b"ok")
            return

        if url.path.startswith("/dl/"):
            self.grab(url.path)
            return

        if url.path == "/api":
            params = parse_qs(url.query)
            t = (params.get("t") or [""])[0]
            if t == "caps":
                self.send_body(200, "application/xml", caps_xml())
            elif t in ("search", "movie", "tvsearch"):
                self.send_body(200, "application/xml", handle_search(params, host))
            else:
                self.send_body(400, "application/xml", error_xml(202, f"unknown t={t}"))
            return

        self.send_body(404, "text/plain", b"not found")

    def grab(self, path: str) -> None:
        m = re.match(r"^/dl/(\d+)(?:\.torrent)?$", path)
        if not m:
            self.send_body(404, "text/plain", b"bad file id")
            return
        try:
            blob = torrent_blob(m.group(1))
        except ValueError:  # not bencode: login page or error
            log.error("download-file/%s did not return a torrent; cookie expired?", m.group(1))
            self.send_body(502, "application/xml", error_xml(900, "filmix returned non-torrent"))
            return
        self.send_body(200, "application/x-bittorrent", blob)


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("FILMIX_LOG", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    global CFG, SESSION
    CFG = Config()
    SESSION = http_session()
    server = ThreadingHTTPServer((CFG.bind, CFG.port), Handler)
    log.info("filmix-torznab listening on %s:%d -> %s", CFG.bind, CFG.port, CFG.base_url)
    server.serve_forever()


if __name__ == "__main__":
    main()
