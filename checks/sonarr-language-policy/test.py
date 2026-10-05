"""Exercise the policy through an isolated, real Sonarr HTTP interface."""

import json
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request


def stop(process):
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def main():
    sonarr, policy = sys.argv[1:3]
    with tempfile.TemporaryDirectory(prefix="sonarr-policy-test-") as directory:
        root = Path(directory)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        key = "a" * 32  # Only authenticates this disposable loopback instance.
        config = root / "config.xml"
        config.write_text(
            f"<Config><Port>{port}</Port><BindAddress>127.0.0.1</BindAddress>"
            f"<ApiKey>{key}</ApiKey><AuthenticationMethod>External</AuthenticationMethod>"
            "<AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>"
            "<LaunchBrowser>False</LaunchBrowser><AnalyticsEnabled>False</AnalyticsEnabled>"
            "<LogLevel>Error</LogLevel></Config>"
        )
        url = f"http://127.0.0.1:{port}/api/v3"
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def api(resource, body=None, method=None):
            request = urllib.request.Request(
                url + "/" + resource,
                data=None if body is None else json.dumps(body).encode(),
                method=method,
                headers={"X-Api-Key": key, "Content-Type": "application/json"},
            )
            with opener.open(request, timeout=10) as response:
                return json.load(response)

        def start(log):
            process = subprocess.Popen(
                [sonarr, "-nobrowser", "-data=" + directory],
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            for _ in range(120):
                try:
                    api("system/status")
                    return process
                except (OSError, ValueError):
                    if process.poll() is not None:
                        raise RuntimeError((root / "stdout").read_text())
                    time.sleep(0.25)
            stop(process)
            raise RuntimeError("Disposable Sonarr did not start")

        with (root / "stdout").open("w") as log:
            process = start(log)
            stop(process)
            # Seed only a fictional series in the external application's database.
            # POST /series fetches SkyHook metadata; this fixture keeps the check offline.
            with sqlite3.connect(root / "sonarr.db") as database:
                database.execute(
                    "INSERT INTO Series (TvdbId,TvRageId,Title,TitleSlug,CleanTitle,Status,"
                    "Images,Path,Monitored,SeasonFolder,Runtime,SeriesType,UseSceneNumbering,"
                    "Seasons,Genres,SortTitle,QualityProfileId,Tags,Added,TvMazeId,OriginalLanguage) "
                    "VALUES (1234567,0,'Policy Fixture','policy-fixture','policyfixture',0,"
                    "'[]',?,0,1,24,0,0,'[]','[]','policy fixture',1,'[]',"
                    "'2026-01-01 00:00:00',0,8)",
                    (str(root / "media" / "Policy Fixture"),),
                )
            process = start(log)
            try:
                initial_profiles = api("qualityprofile")
                if policy != "-":
                    subprocess.run(
                        [sys.executable, policy, "--url", url, "--config-xml", str(config),
                         "--backup", str(root / "backup.json")],
                        check=True,
                    )
                parsed = api("parse?" + urllib.parse.urlencode(
                    {"title": "Policy.Fixture.S01E01.1080p.WEB-DL.JPN.ENG.SUBS-GROUP"}
                ))
                assert parsed.get("series"), "Fixture did not map to a series"
                profile = api("qualityprofile/1")
                assert parsed["customFormatScore"] < profile["minFormatScore"], (
                    "English-subtitled Japanese release is allowed: "
                    f"score={parsed['customFormatScore']}, minimum={profile['minFormatScore']}"
                )
                print("English-only release rejected")
                title = "Policy.Fixture.S01E01.1080p.WEB-DL.JPN.RUS.FORCED.SUBS-GROUP"
                parsed = api("parse?" + urllib.parse.urlencode({"title": title}))
                assert parsed["customFormatScore"] < profile["minFormatScore"], (
                    "Russian forced subtitles alone must not qualify: " + title
                )
                print("Forced subtitles alone rejected")
                # An unrelated preference must never buy its way past the RU gate.
                bonus = api("customformat", {
                    "name": "Unrelated quality bonus",
                    "includeCustomFormatWhenRenaming": False,
                    "specifications": [{"name": "1080p", "implementation": "ReleaseTitleSpecification",
                                        "negate": False, "required": True,
                                        "fields": [{"name": "value", "value": "1080p"}]}],
                }, "POST")
                profile = api("qualityprofile/1")
                for item in profile["formatItems"]:
                    if item["format"] == bonus["id"]:
                        item["score"] = 20000
                api("qualityprofile/1", profile, "PUT")
                subprocess.run(
                    [sys.executable, policy, "--url", url, "--config-xml", str(config),
                     "--backup", str(root / "backup.json")], check=True,
                )
                parsed = api("parse?" + urllib.parse.urlencode(
                    {"title": "Policy.Fixture.S01E01.1080p.WEB-DL.JPN.ENG.SUBS-GROUP"}
                ))
                profile = api("qualityprofile/1")
                assert parsed["customFormatScore"] < profile["minFormatScore"], (
                    "Unrelated bonus bypassed Russian requirement"
                )
                print("Unrelated format score cannot bypass Russian requirement")
                title = "Policy.Fixture.S01E01.1080p.WEB-DL.JPN.RUS_FORCED_SUBS-GROUP"
                parsed = api("parse?" + urllib.parse.urlencode({"title": title}))
                assert parsed["customFormatScore"] < profile["minFormatScore"], (
                    "Underscore-separated Russian forced subtitles alone qualify"
                )
                cases = [
                    ("RUS.JPN", True),
                    ("RUS.Audio.JPN", True),
                    ("JPN.RUS.SUBS", True),
                    ("JPN.Russian.Subtitles", True),
                    ("JPN.русские субтитры", True),
                    ("JPN.озвучка русская", True),
                    ("JPN.ENG.SUBS", False),
                    ("JPN.MultiSub", False),
                    ("Dual-Audio.Multi-Subs", False),
                    ("JPN", False),
                    ("JPN.RUS.ForcedSubs", False),
                    ("JPN.RUS.SUBS.Signs.Songs", False),
                    ("JPN.русские субтитры.надписи", False),
                    ("RUS.Audio.JPN.RUS.ForcedSubs", True),
                ]
                for profile in api("qualityprofile"):
                    series = api("series/1")
                    series["qualityProfileId"] = profile["id"]
                    api("series/1", series, "PUT")
                    for markers, expected in cases:
                        title = "Policy.Fixture.S01E01.1080p.WEB-DL." + markers + "-GROUP"
                        parsed = api("parse?" + urllib.parse.urlencode({"title": title}))
                        assert parsed.get("series"), "Fixture not mapped: " + title
                        accepted = parsed["customFormatScore"] >= profile["minFormatScore"]
                        assert accepted == expected, (
                            f"{profile['name']}: {markers}: score={parsed['customFormatScore']}, "
                            f"minimum={profile['minFormatScore']}, expected accepted={expected}"
                        )
                    original = next(p for p in initial_profiles if p["id"] == profile["id"])
                    for field in ["name", "items", "cutoff", "upgradeAllowed", "minUpgradeFormatScore"]:
                        assert profile[field] == original[field], "Unrelated quality choice changed"
                media = api("config/mediamanagement")
                assert media["importExtraFiles"]
                assert {"srt", "ass", "ssa", "vtt"} <= set(media["extraFileExtensions"].split(","))
                saved_profiles = api("qualityprofile")
                saved_formats = api("customformat")
                backup_bytes = (root / "backup.json").read_bytes()
                result = subprocess.run(
                    [sys.executable, policy, "--url", url, "--config-xml", str(config),
                     "--backup", str(root / "backup.json")], check=True, capture_output=True, text=True,
                )
                assert result.stdout.strip() == "Russian language policy reconciled", result.stdout
                assert api("qualityprofile") == saved_profiles
                assert api("customformat") == saved_formats
                assert api("config/mediamanagement") == media
                assert (root / "backup.json").read_bytes() == backup_bytes
                print(f"{len(cases)} acceptance cases passed in every profile; reconciliation is idempotent")
            finally:
                stop(process)


if __name__ == "__main__":
    main()
