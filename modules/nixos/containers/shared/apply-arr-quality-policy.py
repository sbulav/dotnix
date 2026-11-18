"""Reconcile active/default arr profiles: clean HD/UHD only, prefer UHD."""

import argparse
from copy import deepcopy
import json
import os
from pathlib import Path
import time
import urllib.request
import xml.etree.ElementTree as ET


PROFILES = {"Any", "HD - 720p/1080p"}
QUALITIES = {
    "HDTV-720p", "HDTV-1080p", "HDTV-2160p",
    "WEBDL-720p", "WEBDL-1080p", "WEBDL-2160p",
    "WEBRip-720p", "WEBRip-1080p", "WEBRip-2160p",
    "Bluray-720p", "Bluray-1080p", "Bluray-2160p",
    "Remux-1080p", "Remux-2160p",
    "Bluray-1080p Remux", "Bluray-2160p Remux",
}


class Api:
    def __init__(self, url, key):
        self.url = url.rstrip("/")
        self.key = key
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def request(self, resource, body=None):
        request = urllib.request.Request(
            self.url + "/" + resource,
            data=None if body is None else json.dumps(body).encode(),
            method="GET" if body is None else "PUT",
            headers={"X-Api-Key": self.key, "Content-Type": "application/json"},
        )
        with self.opener.open(request, timeout=15) as response:
            data = response.read()
            return json.loads(data) if data else None


def reconcile(api, backup):
    profiles = api.request("qualityprofile")
    # Profiles contain no indexer/download-client credentials. Never overwrite
    # the first rollback snapshot, including on subsequent container starts.
    backup = Path(backup)
    if not backup.exists():
        descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            json.dump({"qualityprofile": profiles}, stream, indent=2)

    for current in profiles:
        if current["name"] not in PROFILES:
            continue
        wanted = deepcopy(current)
        cutoff = None
        for item in wanted["items"]:
            qualities = item.get("items") or [item]
            for quality in qualities:
                quality["allowed"] = quality["quality"]["name"] in QUALITIES
                if quality["quality"]["name"] == "Bluray-2160p":
                    cutoff = item.get("id", quality["quality"]["id"])
            item["allowed"] = any(q["allowed"] for q in qualities)
        if cutoff is None:
            raise ValueError("Missing UHD cutoff in profile: " + current["name"])

        # Source preferences break ties within a resolution, not across them:
        # e.g. HDTV-1080p should outrank even Blu-ray 720p.
        wanted["items"].sort(key=lambda item: max(
            q["quality"]["resolution"] for q in (item.get("items") or [item])
        ))
        wanted["cutoff"] = cutoff
        wanted["upgradeAllowed"] = True
        # Preserve all language/custom-format scores, thresholds and metadata.
        if wanted != current:
            api.request("qualityprofile/" + str(current["id"]), wanted)
            print("Applied HD/UHD policy: " + current["name"])
    print("HD/UHD quality policy reconciled")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--config-xml", required=True)
    parser.add_argument("--backup", required=True)
    args = parser.parse_args()
    for _ in range(150):
        try:
            key = ET.parse(args.config_xml).findtext("ApiKey")
            if not key:
                raise ValueError("arr API key not initialized")
            api = Api(args.url, key)
            api.request("system/status")
            break
        except (OSError, ET.ParseError, ValueError):
            time.sleep(2)
    else:
        raise RuntimeError("arr API did not become ready")
    reconcile(api, args.backup)


if __name__ == "__main__":
    main()
