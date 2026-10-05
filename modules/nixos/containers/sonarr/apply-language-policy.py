"""Reconcile Sonarr's database-only Russian release policy over its HTTP API."""

import argparse
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET


# These are .NET regular expressions, evaluated by Sonarr itself. Generic
# MULTI/Dual-Audio/MultiSub and uploader/indexer names convey no RU evidence.
# Unlike \b, these treat '_' as a separator, as release names commonly do.
START = r"(?<![\p{L}\p{N}])"
END = r"(?![\p{L}\p{N}])"
RU = rf"{START}(?:rus|ru|russian|рус(?:ский|ская|ские|ских|ское)?){END}"
SEPARATOR = r"[ ._:+\-]*"
RU_AUDIO = (
    rf"{START}(?:rus|ru|russian){SEPARATOR}(?:audio|dub(?:bed)?|voice(?:over)?){END}"
    rf"|{START}(?:audio|dub(?:bed)?|voice(?:over)?){SEPARATOR}(?:rus|ru|russian){END}"
    rf"|{START}рус(?:ский|ская|ское)?{SEPARATOR}(?:озвучка|дубляж|аудио){END}"
    rf"|{START}(?:озвучка|дубляж|аудио){SEPARATOR}рус(?:ский|ская|ское)?{END}"
)
RU_SUBS = (
    rf"{START}(?:rus|ru|russian){SEPARATOR}(?:(?:full|soft|hard(?:coded)?){SEPARATOR})?"
    rf"(?:sub(?:title)?s?|subbed){END}"
    rf"|{START}(?:sub(?:title)?s?|subbed){SEPARATOR}(?:rus|ru|russian){END}"
    rf"|{START}рус(?:ские|ских)?{SEPARATOR}(?:полные{SEPARATOR})?(?:субтитры|сабы){END}"
    rf"|{START}(?:субтитры|сабы){SEPARATOR}рус(?:ские|ских)?{END}"
)
PARTIAL_SUBS = (
    rf"{START}(?:forced(?:{SEPARATOR}subs?)?|signs?(?:{SEPARATOR}songs?)?|"
    rf"songs?|lyrics|partial|форс(?:ированные)?|надписи|песни){END}"
)
FULL_RU_SUBS = rf"^(?!.*(?:{PARTIAL_SUBS})).*(?:{RU_SUBS})"
# The language parser also calls "RUS SUBS" Russian audio. Exclude those
# subtitle-only claims (and ambiguous partial tracks) unless RU audio is explicit.
SUBTITLE_ONLY = rf"^(?!.*(?:{RU_AUDIO}))(?=.*(?:{RU}))(?=.*(?:{RU_SUBS}|{PARTIAL_SUBS})).*"


def title(name, expression, negate=False):
    return {
        "name": name,
        "implementation": "ReleaseTitleSpecification",
        "negate": negate,
        "required": True,
        "fields": [{"name": "value", "value": expression}],
    }


def language(name, value, negate=False):
    return {
        "name": name,
        "implementation": "LanguageSpecification",
        "negate": negate,
        "required": True,
        "fields": [{"name": "value", "value": value},
                   {"name": "exceptLanguage", "value": False}],
    }


FORMATS = [
    ({"name": "RU Audio", "includeCustomFormatWhenRenaming": False,
      "specifications": [language("Russian", 11),
                         title("Not a subtitle-only claim", SUBTITLE_ONLY, True)]}, 500),
    ({"name": "RU+JP Dual Audio", "includeCustomFormatWhenRenaming": False,
      "specifications": [language("Russian", 11), language("Japanese", 8),
                         title("Not a subtitle-only claim", SUBTITLE_ONLY, True)]}, 1000),
    ({"name": "RU Audio (explicit)", "includeCustomFormatWhenRenaming": False,
      "specifications": [title("Russian audio declared", RU_AUDIO)]}, 500),
    ({"name": "RU Subtitles (explicit)", "includeCustomFormatWhenRenaming": False,
      "specifications": [title("Russian subtitles declared", RU_SUBS),
                         title("Not partial subtitles", PARTIAL_SUBS, True)]}, 500),
    # Negative gates make the policy independent of unrelated positive formats.
    # Their score is set below the sum of every possible bonus in each profile.
    ({"name": "No RU evidence", "includeCustomFormatWhenRenaming": False,
      "specifications": [language("Not Russian", 11, True),
                         title("No explicit Russian audio", RU_AUDIO, True),
                         title("No full Russian subtitles", FULL_RU_SUBS, True)]}, None),
    ({"name": "RU partial subtitles only", "includeCustomFormatWhenRenaming": False,
      "specifications": [title("Subtitle-only claim", SUBTITLE_ONLY),
                         title("No full Russian subtitles", FULL_RU_SUBS, True)]}, None),
]


class Api:
    def __init__(self, url, key):
        self.url = url.rstrip("/")
        self.key = key
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def request(self, resource, body=None, method=None):
        request = urllib.request.Request(
            self.url + "/" + resource,
            data=None if body is None else json.dumps(body).encode(),
            method=method,
            headers={"X-Api-Key": self.key, "Content-Type": "application/json"},
        )
        with self.opener.open(request, timeout=15) as response:
            data = response.read()
            return json.loads(data) if data else None


def canonical_format(resource):
    return {
        "name": resource["name"],
        "includeCustomFormatWhenRenaming": resource.get("includeCustomFormatWhenRenaming", False),
        "specifications": [
            {"name": spec["name"], "implementation": spec["implementation"],
             "negate": spec.get("negate", False), "required": spec.get("required", False),
             "fields": {field["name"]: field.get("value") for field in spec["fields"]}}
            for spec in resource["specifications"]
        ],
    }


def reconcile(api, backup):
    existing = api.request("customformat")
    profiles = api.request("qualityprofile")
    media = api.request("config/mediamanagement")
    # This rollback snapshot contains no indexer or download-client credentials.
    backup = Path(backup)
    if not backup.exists():
        descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            json.dump({"customformat": existing, "qualityprofile": profiles,
                       "mediamanagement": media}, stream, indent=2)

    scores = {}
    for wanted, score in FORMATS:
        current = next((f for f in existing if f["name"] == wanted["name"]), None)
        if current is None:
            current = api.request("customformat", wanted, "POST")
            print(f"Created custom format: {wanted['name']}")
        elif canonical_format(current) != canonical_format(wanted):
            api.request("customformat/" + str(current["id"]),
                        {**wanted, "id": current["id"]}, "PUT")
            print(f"Updated custom format: {wanted['name']}")
        scores[current["id"]] = score

    # Creating a format adds a zero-score entry to every profile; read them again.
    for current in api.request("qualityprofile"):
        positive_total = sum(max(0, scores.get(item["format"], item["score"]) or 0)
                             for item in current["formatItems"])
        rejection_score = -max(10000, positive_total + 500)
        profile_scores = {format_id: score if score is not None else rejection_score
                          for format_id, score in scores.items()}
        wanted = {**current, "minFormatScore": 500,
                  "cutoffFormatScore": max(500, current["cutoffFormatScore"]),
                  "formatItems": [{**item, "score": profile_scores.get(item["format"], item["score"])}
                                  for item in current["formatItems"]]}
        if wanted != current:
            api.request("qualityprofile/" + str(current["id"]), wanted, "PUT")
            print(f"Applied Russian requirement: {current['name']}")

    extensions = [ext.strip() for ext in media["extraFileExtensions"].split(",") if ext.strip()]
    extensions = list(dict.fromkeys(extensions + ["srt", "ass", "ssa", "vtt"]))
    wanted = {**media, "importExtraFiles": True, "enableMediaInfo": True,
              "extraFileExtensions": ",".join(extensions)}
    if wanted != media:
        api.request("config/mediamanagement/" + str(media["id"]), wanted, "PUT")
        print("Enabled external subtitle import")
    print("Russian language policy reconciled")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8989/api/v3")
    parser.add_argument("--config-xml", required=True)
    parser.add_argument("--backup", required=True)
    args = parser.parse_args()
    api = None
    for _ in range(150):
        try:
            key = ET.parse(args.config_xml).findtext("ApiKey")
            if not key:
                raise ValueError("Sonarr API key not initialized")
            api = Api(args.url, key)
            api.request("system/status")
            break
        except (OSError, ET.ParseError, ValueError):
            time.sleep(2)
    else:
        raise RuntimeError("Sonarr API did not become ready")
    reconcile(api, args.backup)


if __name__ == "__main__":
    main()
