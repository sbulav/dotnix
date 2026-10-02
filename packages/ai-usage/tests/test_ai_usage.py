from __future__ import annotations

import datetime as dt
import importlib.util
import os
import pathlib
import stat
import sys
import tempfile
import time
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "ai_usage.py"
SPEC = importlib.util.spec_from_file_location("ai_usage", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
ai_usage = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ai_usage
SPEC.loader.exec_module(ai_usage)


UTC = dt.timezone.utc


class ClaudeLimitsTest(unittest.TestCase):
  def test_reads_flat_and_unique_model_scoped_windows(self) -> None:
    payload = {
      "five_hour": {"utilization": 78.0},
      "seven_day": {"utilization": 12.0},
      "limits": [
        {"kind": "session", "percent": 78, "scope": None},
        {
          "kind": "weekly_scoped",
          "percent": 17,
          "resets_at": "2026-09-15T03:00:00+00:00",
          "scope": {"model": {"id": "claude-fable-5", "display_name": "Fable"}},
        },
        {
          "kind": "weekly_scoped",
          "percent": 99,
          "scope": {"model": {"display_name": "Fable"}},
        },
        {
          "kind": "five_hour_scoped",
          "percent": 95,
          "scope": {"model": {"display_name": "Fable"}},
        },
        {
          "kind": "weekly_scoped",
          "percent": 42,
          "scope": {"model": {"id": "claude-opus-5", "display_name": None}},
        },
        {"kind": "weekly_scoped", "percent": "unknown", "scope": {"model": {"display_name": "Opus"}}},
      ],
    }

    limits = ai_usage.claude_limits_from_payload(payload)

    self.assertEqual(
      [(entry["label"], entry["percent"]) for entry in limits],
      [
        ("Session (5-hour)", 0.78),
        ("Weekly (7-day)", 0.12),
        ("Fable Weekly", 0.17),
        ("Fable Session", 0.95),
        ("claude-opus-5 Weekly", 0.42),
      ],
    )

  def test_fraction_payload_keeps_fraction_scale(self) -> None:
    limits = ai_usage.claude_limits_from_payload({
      "five_hour": {"utilization": 0.78},
      "limits": [
        {
          "kind": "weekly_scoped",
          "percent": 0.42,
          "scope": {"model": {"display_name": "Fable"}},
        },
      ],
    })
    self.assertEqual([entry["percent"] for entry in limits], [0.78, 0.42])


class CodexLimitsTest(unittest.TestCase):
  def test_preserves_over_limit_percentage_and_labels_windows(self) -> None:
    weekly = ai_usage.codex_limit_window({
      "usedPercent": 108,
      "windowDurationMins": 10080,
      "resetsAt": 1788200000,
    })
    session = ai_usage.codex_limit_window({"usedPercent": 34, "windowDurationMins": 300})

    assert weekly is not None and session is not None
    self.assertEqual(weekly["label"], "Weekly (7-day)")
    self.assertEqual(weekly["percent"], 1.08)
    self.assertEqual(weekly["resetsAtMs"], 1788200000000)
    self.assertEqual(session["label"], "5h window")


class CodexChildEnvTest(unittest.TestCase):
  PARENT_ENV = {
    "AI_USAGE_CODEX_PROXY": "socks5h://192.168.89.207:20170",
    "HTTP_PROXY": "http://fwdproxy.pyn.ru:4443",
    "HTTPS_PROXY": "http://fwdproxy.pyn.ru:4443",
    "http_proxy": "http://fwdproxy.pyn.ru:4443",
    "https_proxy": "http://fwdproxy.pyn.ru:4443",
    "NO_PROXY": "localhost,127.0.0.1,::1,pyn.ru,chatgpt.com",
    "no_proxy": "localhost,127.0.0.1,::1,pyn.ru,chatgpt.com",
    "PATH": "/bin",
  }

  def test_override_pins_child_to_vless_and_drops_carve_outs(self) -> None:
    with mock.patch.dict(os.environ, self.PARENT_ENV, clear=True):
      child = ai_usage.codex_child_env()
    for key in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
      self.assertEqual(child[key], "socks5h://192.168.89.207:20170")
    for key in ("NO_PROXY", "no_proxy"):
      self.assertEqual(child[key], "localhost,127.0.0.1,::1")

  def test_without_override_child_inherits_parent_env(self) -> None:
    parent = {key: value for key, value in self.PARENT_ENV.items() if key != "AI_USAGE_CODEX_PROXY"}
    with mock.patch.dict(os.environ, parent, clear=True):
      child = ai_usage.codex_child_env()
    self.assertEqual(child["HTTPS_PROXY"], "http://fwdproxy.pyn.ru:4443")
    self.assertEqual(child["NO_PROXY"], "localhost,127.0.0.1,::1,pyn.ru,chatgpt.com")


class CodexProbeTest(unittest.TestCase):
  def test_real_rpc_server_with_unanswered_account_read(self) -> None:
    with tempfile.TemporaryDirectory() as directory:
      server = pathlib.Path(directory) / "codex"
      server.write_text(f"#!{sys.executable}\n" + '''
import json
import sys

for line in sys.stdin:
  request = json.loads(line)
  method = request["method"]
  if method == "initialize":
    result = {}
  elif method == "account/rateLimits/read":
    result = {"rateLimits": {
      "planType": "pro",
      "primary": {"usedPercent": 36, "windowDurationMins": 10080},
    }}
  else:
    continue  # account/read never answers, as in the affected app-server.
  print(json.dumps({"id": request["id"], "result": result}), flush=True)
''')
      server.chmod(0o700)
      started = time.monotonic()
      result = ai_usage.probe_codex(str(server))
      self.assertTrue(result.ok)
      self.assertEqual(result.tier_label, "Pro")
      self.assertEqual(result.limits[0]["percent"], 0.36)
      self.assertLess(time.monotonic() - started, 4)

  def probe(self, limits: dict, account: dict | Exception) -> tuple:
    process = mock.Mock()
    methods = []

    def request(_process, _request_id, method, params=None, timeout=8):
      methods.append((method, timeout))
      if method == "account/rateLimits/read":
        return {"result": {"rateLimits": limits}}
      if method == "account/read":
        if isinstance(account, Exception):
          raise account
        return {"result": {"account": account}}
      return {"result": {}}

    with mock.patch.object(ai_usage.shutil, "which", return_value="/bin/codex"), \
         mock.patch.object(ai_usage.subprocess, "Popen", return_value=process), \
         mock.patch.object(ai_usage, "rpc_request", side_effect=request):
      result = ai_usage.probe_codex()
    process.terminate.assert_called_once()
    return result, methods

  def test_plan_in_limits_skips_unanswered_account_request(self) -> None:
    result, methods = self.probe({
      "planType": "pro",
      "primary": {"usedPercent": 36, "windowDurationMins": 10080},
    }, TimeoutError("account/read"))
    self.assertTrue(result.ok)
    self.assertEqual(result.tier_label, "Pro")
    self.assertEqual(result.limits[0]["percent"], 0.36)
    self.assertEqual([method for method, _ in methods], ["initialize", "account/rateLimits/read"])

  def test_missing_plan_uses_account_after_limits(self) -> None:
    result, methods = self.probe({
      "primary": {"usedPercent": 20, "windowDurationMins": 300},
    }, {"type": "chatgpt", "planType": "plus"})
    self.assertTrue(result.ok)
    self.assertEqual(result.tier_label, "Plus")
    self.assertEqual(methods[-2:], [("account/rateLimits/read", 8), ("account/read", 2)])

  def test_failed_optional_account_request_preserves_limits(self) -> None:
    for error in (TimeoutError("account/read"), RuntimeError("RPC error")):
      with self.subTest(error=error):
        result, _ = self.probe({
          "primary": {"usedPercent": 20, "windowDurationMins": 300},
        }, error)
        self.assertTrue(result.ok)
        self.assertEqual(result.tier_label, "")
        self.assertEqual(result.limits[0]["percent"], 0.2)

  def test_no_active_limits_still_reports_unavailable(self) -> None:
    result, _ = self.probe({"planType": "pro"}, {})
    self.assertFalse(result.ok)
    self.assertEqual(result.status_text, "Codex limits unavailable")


class CacheMergeTest(unittest.TestCase):
  def test_failed_probe_keeps_only_unreset_previous_windows(self) -> None:
    now = dt.datetime(2026, 8, 31, 12, tzinfo=UTC)
    old = {
      "tierLabel": "Max 20x",
      "lastSuccessAt": "2026-08-31T11:50:00+00:00",
      "lastSuccessAtMs": 1788177000000,
      "limits": [
        {"label": "Session", "percent": 0.8, "resetsAt": "2026-08-31T11:00:00+00:00"},
        {"label": "Hourly", "percent": 0.6, "resetsAt": "", "resetsAtMs": 1788174000000},
        {"label": "Weekly", "percent": 0.4, "resetsAt": "2026-09-01T11:00:00+00:00"},
      ],
    }

    merged = ai_usage.merge_probe(
      "claude",
      "Claude Code",
      ai_usage.Probe(False, status_text="Claude limits unavailable"),
      old,
      now,
    )

    self.assertFalse(merged["probeOk"])
    self.assertEqual(merged["tierLabel"], "Max 20x")
    self.assertEqual([entry["label"] for entry in merged["limits"]], ["Weekly"])
    self.assertEqual(merged["lastSuccessAt"], old["lastSuccessAt"])
    self.assertEqual(merged["lastSuccessAtMs"], old["lastSuccessAtMs"])

  def test_success_replaces_cache_and_records_freshness(self) -> None:
    now = dt.datetime(2026, 8, 31, 12, tzinfo=UTC)
    merged = ai_usage.merge_probe(
      "codex",
      "Codex",
      ai_usage.Probe(True, "Plus", ({"label": "5h window", "percent": 0.2, "resetsAt": ""},)),
      {"limits": [{"label": "old", "percent": 0.9, "resetsAt": ""}]},
      now,
    )
    self.assertTrue(merged["probeOk"])
    self.assertEqual(merged["tierLabel"], "Plus")
    self.assertEqual([entry["label"] for entry in merged["limits"]], ["5h window"])
    self.assertEqual(merged["lastSuccessAt"], "2026-08-31T12:00:00+00:00")
    self.assertEqual(merged["lastSuccessAtMs"], 1788177600000)


class StateFileTest(unittest.TestCase):
  def test_atomic_state_is_private_and_readable(self) -> None:
    with tempfile.TemporaryDirectory() as directory:
      destination = pathlib.Path(directory) / "nested" / "state.json"
      payload = {"schemaVersion": 1, "providers": []}
      ai_usage.write_state(destination, payload)

      self.assertEqual(ai_usage.read_state(destination), payload)
      self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
      self.assertEqual(stat.S_IMODE(destination.parent.stat().st_mode), 0o700)


if __name__ == "__main__":
  unittest.main()
