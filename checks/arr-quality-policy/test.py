"""Exercise HD/UHD policy through disposable, real Radarr/Sonarr HTTP interfaces."""

import json
from pathlib import Path
import socket
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


def exercise(app, binary, policy):
    with tempfile.TemporaryDirectory(prefix=app + "-quality-test-") as directory:
        root = Path(directory)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        key = "b" * 32  # Only authenticates this disposable loopback instance.
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
                data = response.read()
                return json.loads(data) if data else None

        with (root / "stdout").open("w") as log:
            process = subprocess.Popen(
                [binary, "-nobrowser", "-data=" + directory],
                stdout=log, stderr=subprocess.STDOUT,
            )
            try:
                for _ in range(120):
                    try:
                        api("system/status")
                        break
                    except (OSError, ValueError):
                        if process.poll() is not None:
                            raise RuntimeError((root / "stdout").read_text())
                        time.sleep(0.25)
                else:
                    raise RuntimeError("Disposable " + app + " did not start")

                # Non-zero language preferences must survive profile edits.
                custom_format = api("customformat", {
                    "name": "Existing RU preference", "includeCustomFormatWhenRenaming": False,
                    "specifications": [{"name": "Russian", "implementation": "LanguageSpecification",
                                        "negate": False, "required": True,
                                        "fields": [{"name": "value", "value": 11}]}],
                }, "POST")
                for profile in api("qualityprofile"):
                    profile["minFormatScore"] = 500
                    profile["cutoffFormatScore"] = 1500
                    for item in profile["formatItems"]:
                        if item["format"] == custom_format["id"]:
                            item["score"] = 1000
                    api("qualityprofile/" + str(profile["id"]), profile, "PUT")
                initial = api("qualityprofile")
                backup = root / "backup.json"
                command = [sys.executable, policy, "--url", url,
                           "--config-xml", str(config), "--backup", str(backup)]
                if policy != "-":
                    subprocess.run(command, check=True)
                profiles = api("qualityprofile")
                for profile in profiles:
                    original = next(p for p in initial if p["id"] == profile["id"])
                    if profile["name"] not in ("Any", "HD - 720p/1080p"):
                        assert profile == original, "Unused profile changed: " + profile["name"]
                        continue
                    allowed = []
                    for item in profile["items"]:
                        if item.get("items"):
                            allowed.extend(q["quality"] for q in item["items"]
                                           if item["allowed"] and q["allowed"])
                        elif item["allowed"]:
                            allowed.append(item["quality"])
                    names = {q["name"] for q in allowed}
                    assert "TELESYNC" not in names, "Cinema recording permitted: " + profile["name"]
                    assert {q["resolution"] for q in allowed} == {720, 1080, 2160}, names
                    assert {"HDTV-720p", "WEBDL-1080p", "Bluray-2160p"} <= names, names
                    assert not {"Unknown", "CAM", "WORKPRINT", "TELECINE", "DVDSCR",
                                "SDTV", "DVD", "BR-DISK", "Raw-HD"} & names, names
                    cutoff = next(q for q in profile["items"]
                                  if q.get("id", q.get("quality", {}).get("id")) == profile["cutoff"])
                    assert cutoff["quality"]["name"] == "Bluray-2160p", cutoff
                    assert profile["upgradeAllowed"], "Upgrades disabled"
                    order = [q["resolution"] for q in allowed]
                    assert order == sorted(order), "Higher resolution not preferred: " + str(order)
                    for field in ("minFormatScore", "cutoffFormatScore", "minUpgradeFormatScore",
                                  "formatItems", "language"):
                        assert profile.get(field) == original.get(field), "Language scoring changed"

                if policy != "-":
                    backup_bytes = backup.read_bytes()
                    subprocess.run(command, check=True)
                    assert api("qualityprofile") == profiles, "Policy is not idempotent"
                    assert backup.read_bytes() == backup_bytes, "Rollback snapshot overwritten"
                    assert json.loads(backup_bytes)["qualityprofile"] == initial
                print(app + ": HD/UHD accepted, cinema/SD rejected, UHD preferred; language scores preserved")
            finally:
                stop(process)


if __name__ == "__main__":
    exercise(sys.argv[1], sys.argv[2], sys.argv[3])
