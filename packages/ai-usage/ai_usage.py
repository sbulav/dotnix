#!/usr/bin/env python3
"""Collect Claude Code and Codex subscription limits into one safe JSON state.

The provider probes and record contract are adapted from Omarchy's MIT-licensed
agent usage collectors. This deliberately omits transcript/token analytics: the
only data retained is the subscription plan, live limit windows, reset times,
and display-safe failure state.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import datetime as dt
import fcntl
import json
import os
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable


SCHEMA_VERSION = 1
CLAUDE_USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
CLAUDE_AUTH_HELP = "Run `claude auth login` to restore Claude usage."
CODEX_AUTH_HELP = "Run `codex login` to restore Codex usage."


@dataclasses.dataclass(frozen=True)
class Probe:
  ok: bool
  tier_label: str = ""
  limits: tuple[dict[str, Any], ...] = ()
  status_text: str = ""
  help_text: str = ""


def utc_now() -> dt.datetime:
  return dt.datetime.now(dt.timezone.utc)


def isoformat(value: dt.datetime) -> str:
  return value.astimezone(dt.timezone.utc).isoformat()


def epoch_ms(value: dt.datetime | None) -> int:
  return int(value.timestamp() * 1000) if value is not None else 0


def number(value: Any, default: float = 0.0) -> float:
  try:
    parsed = float(value)
    return parsed if parsed == parsed else default
  except (TypeError, ValueError):
    return default


def parse_time(value: Any) -> dt.datetime | None:
  raw = str(value or "").strip()
  if not raw:
    return None
  try:
    parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
  except ValueError:
    return None
  if parsed.tzinfo is None:
    parsed = parsed.replace(tzinfo=dt.timezone.utc)
  return parsed.astimezone(dt.timezone.utc)


def normalize_reset_at(value: Any) -> str:
  if value is None:
    return ""
  raw = str(value).strip()
  if not raw:
    return ""
  if raw.isdigit():
    stamp = int(raw)
    if stamp < 1_000_000_000_000:
      stamp *= 1000
    try:
      return isoformat(dt.datetime.fromtimestamp(stamp / 1000, dt.timezone.utc))
    except (OverflowError, OSError, ValueError):
      return raw
  parsed = parse_time(raw)
  return isoformat(parsed) if parsed is not None else raw


def open_limits(entries: Any, now: dt.datetime | None = None) -> list[dict[str, Any]]:
  """Keep real limit records whose provider window has not already reset."""
  current = now or utc_now()
  result: list[dict[str, Any]] = []
  if not isinstance(entries, list) and not isinstance(entries, tuple):
    return result
  for raw in entries:
    if not isinstance(raw, dict):
      continue
    label = str(raw.get("label") or "").strip()
    percent = number(raw.get("percent"), -1)
    if not label or percent < 0:
      continue
    reset_at = str(raw.get("resetsAt") or "")
    parsed_reset = parse_time(reset_at)
    reset_at_ms = int(number(raw.get("resetsAtMs"))) or epoch_ms(parsed_reset)
    if (parsed_reset is not None and parsed_reset <= current) or (reset_at_ms > 0 and reset_at_ms <= epoch_ms(current)):
      continue
    entry = {
      "label": label,
      "percent": percent,
      "resetsAt": reset_at,
      "resetsAtMs": reset_at_ms,
    }
    title = str(raw.get("title") or "").strip()
    if title:
      entry["title"] = title
    result.append(entry)
  return result


def claude_config_dir() -> Path:
  return Path(os.path.expandvars(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")))


def claude_login(config_dir: Path | None = None) -> tuple[str, int, str]:
  try:
    payload = json.loads(((config_dir or claude_config_dir()) / ".credentials.json").read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return "", 0, ""
  login = payload.get("claudeAiOauth")
  if not isinstance(login, dict):
    return "", 0, ""
  tier = str(login.get("rateLimitTier") or "")
  subscription = str(login.get("subscriptionType") or "")
  match = re.search(r"max_(\d+x)", tier, re.IGNORECASE)
  if match:
    plan = "Max " + match.group(1)
  elif subscription:
    plan = subscription[:1].upper() + subscription[1:]
  else:
    plan = ""
  return str(login.get("accessToken") or ""), int(number(login.get("expiresAt"))), plan


def parse_utilization(value: Any) -> float:
  try:
    return float(str(value).strip().replace("%", ""))
  except (TypeError, ValueError):
    return float("nan")


def normalize_utilization(value: Any, percent_scale: bool) -> float:
  parsed = parse_utilization(value)
  if not parsed >= 0:
    return -1
  # Anthropic currently returns percentage points, while older payloads used
  # fractions. One response uses one convention, including scoped entries.
  return parsed / 100 if percent_scale or parsed > 1 else parsed


def scoped_window(kind: str) -> str:
  lowered = kind.lower()
  if "month" in lowered:
    return "Monthly"
  if "week" in lowered or "day" in lowered:
    return "Weekly"
  if "hour" in lowered or "session" in lowered:
    return "Session"
  return ""


def claude_limits_from_payload(payload: dict[str, Any]) -> list[dict[str, Any]]:
  session = payload.get("five_hour") if isinstance(payload.get("five_hour"), dict) else None
  weekly = payload.get("seven_day_oauth_apps")
  if not isinstance(weekly, dict):
    weekly = payload.get("seven_day") if isinstance(payload.get("seven_day"), dict) else None

  raw_values: list[Any] = [
    session.get("utilization") if session else None,
    weekly.get("utilization") if weekly else None,
  ]
  scoped = payload.get("limits")
  if isinstance(scoped, list):
    raw_values.extend(entry.get("percent") for entry in scoped if isinstance(entry, dict))
  percent_scale = any(parse_utilization(value) >= 1 for value in raw_values)

  result: list[dict[str, Any]] = []
  for bucket, label in ((session, "Session (5-hour)"), (weekly, "Weekly (7-day)")):
    if bucket is None:
      continue
    percent = normalize_utilization(bucket.get("utilization"), percent_scale)
    if percent >= 0:
      result.append({
        "label": label,
        "percent": percent,
        "resetsAt": normalize_reset_at(bucket.get("resets_at")),
        "resetsAtMs": epoch_ms(parse_time(normalize_reset_at(bucket.get("resets_at")))),
      })

  seen: set[tuple[str, str]] = set()
  if not isinstance(scoped, list):
    return result
  for entry in scoped:
    if not isinstance(entry, dict):
      continue
    scope = entry.get("scope")
    model = scope.get("model") if isinstance(scope, dict) else None
    if not isinstance(model, dict):
      continue
    name = str(model.get("display_name") or model.get("id") or "").strip()
    kind = str(entry.get("kind") or "").strip()
    identity = (name, kind)
    percent = normalize_utilization(entry.get("percent"), percent_scale)
    if not name or identity in seen or percent < 0:
      continue
    seen.add(identity)
    window = scoped_window(kind)
    title = f"{name} {window}" if window else name
    result.append({
      "label": title,
      "title": title,
      "percent": percent,
      "resetsAt": normalize_reset_at(entry.get("resets_at")),
      "resetsAtMs": epoch_ms(parse_time(normalize_reset_at(entry.get("resets_at")))),
    })
  return result


def probe_claude(
  opener: Callable[..., Any] = urllib.request.urlopen,
  config_dir: Path | None = None,
) -> Probe:
  access_token, expires_at_ms, plan = claude_login(config_dir)
  if not access_token:
    return Probe(False, plan, status_text="Waiting for Claude auth", help_text=CLAUDE_AUTH_HELP)
  if expires_at_ms > 0 and expires_at_ms <= time.time() * 1000:
    return Probe(False, plan, status_text="Claude sign-in expired", help_text=CLAUDE_AUTH_HELP)

  request = urllib.request.Request(
    CLAUDE_USAGE_ENDPOINT,
    headers={
      "Authorization": "Bearer " + access_token,
      "anthropic-beta": "oauth-2025-04-20",
      "Accept": "application/json",
    },
  )
  try:
    with opener(request, timeout=10) as response:
      payload = json.loads(response.read().decode("utf-8", errors="replace"))
  except urllib.error.HTTPError as error:
    if error.code in (401, 403):
      help_text = CLAUDE_AUTH_HELP
    elif error.code == 429:
      retry_after = error.headers.get("retry-after", "") if error.headers else ""
      suffix = f" Retry after {retry_after}s." if retry_after else ""
      help_text = "Anthropic is rate-limiting usage checks." + suffix
    else:
      help_text = f"Anthropic usage returned HTTP {error.code}."
    return Probe(False, plan, status_text="Claude limits unavailable", help_text=help_text)
  except (OSError, TimeoutError, json.JSONDecodeError, ValueError):
    return Probe(
      False,
      plan,
      status_text="Claude limits unavailable",
      help_text="Could not reach Anthropic through the configured proxy.",
    )

  if not isinstance(payload, dict):
    return Probe(False, plan, status_text="Claude limits unavailable", help_text="Anthropic returned invalid usage data.")
  limits = tuple(claude_limits_from_payload(payload))
  if not limits:
    return Probe(False, plan, status_text="Claude limits unavailable", help_text="Anthropic returned no active limits.")
  return Probe(True, plan, limits)


def rpc_request(
  process: subprocess.Popen[str],
  request_id: int,
  method: str,
  params: dict[str, Any] | None = None,
  timeout: float = 8,
) -> dict[str, Any]:
  assert process.stdin is not None
  assert process.stdout is not None
  process.stdin.write(json.dumps({"id": request_id, "method": method, "params": params or {}}) + "\n")
  process.stdin.flush()
  deadline = time.time() + timeout
  while time.time() < deadline:
    ready, _, _ = select.select([process.stdout], [], [], min(0.25, max(0, deadline - time.time())))
    if not ready:
      continue
    line = process.stdout.readline()
    if not line:
      break
    try:
      message = json.loads(line)
    except json.JSONDecodeError:
      continue
    if message.get("id") != request_id:
      continue
    if message.get("error"):
      raise RuntimeError(f"{method}: app-server returned an error")
    return message
  raise TimeoutError(method)


def codex_limit_window(window: Any) -> dict[str, Any] | None:
  if not isinstance(window, dict) or window.get("usedPercent") is None:
    return None
  minutes = int(number(window.get("windowDurationMins")))
  if minutes == 10080:
    label = "Weekly (7-day)"
  elif minutes and minutes % 60 == 0:
    label = f"{minutes // 60}h window"
  elif minutes:
    label = f"{minutes}m window"
  else:
    label = "Limit"
  reset = number(window.get("resetsAt"))
  reset_at = isoformat(dt.datetime.fromtimestamp(reset, dt.timezone.utc)) if reset else ""
  return {
    "label": label,
    "percent": number(window.get("usedPercent")) / 100,
    "resetsAt": reset_at,
    "resetsAtMs": int(reset * 1000) if reset else 0,
  }


def probe_codex(command: str | None = None) -> Probe:
  requested = command or os.environ.get("AI_USAGE_CODEX_BIN") or "codex"
  codex = shutil.which(requested)
  if not codex:
    return Probe(False, status_text="Codex unavailable", help_text="codex was not found in PATH.")

  try:
    process = subprocess.Popen(
      [codex, "-s", "read-only", "-a", "on-request", "app-server"],
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
      text=True,
      env=os.environ.copy(),
    )
  except OSError:
    return Probe(False, status_text="Codex unavailable", help_text="Could not start codex app-server.")

  try:
    rpc_request(process, 1, "initialize", {"clientInfo": {"name": "ai-usage", "version": "1"}})
    assert process.stdin is not None
    process.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
    process.stdin.flush()
    account_message = rpc_request(process, 2, "account/read", timeout=8)
    account_result = account_message.get("result") or {}
    account = account_result.get("account")
    if not isinstance(account, dict):
      return Probe(False, status_text="Waiting for Codex auth", help_text=CODEX_AUTH_HELP)
    limits_message = rpc_request(process, 3, "account/rateLimits/read", timeout=8)

    rate_limits = (limits_message.get("result") or {}).get("rateLimits") or {}
    raw_plan = rate_limits.get("planType") or account.get("planType") or account.get("type") or ""
    plan = str(raw_plan).replace("_", " ").title() if raw_plan else ""
    limits = tuple(
      entry
      for entry in (codex_limit_window(rate_limits.get("primary")), codex_limit_window(rate_limits.get("secondary")))
      if entry is not None
    )
    if not limits:
      return Probe(False, plan, status_text="Codex limits unavailable", help_text="Codex returned no active limits.")
    return Probe(True, plan, limits)
  except (OSError, RuntimeError, TimeoutError, ValueError):
    return Probe(
      False,
      status_text="Codex limits unavailable",
      help_text="Could not read Codex limits through app-server and the configured proxy.",
    )
  finally:
    try:
      process.terminate()
      process.wait(timeout=1)
    except (OSError, subprocess.TimeoutExpired):
      try:
        process.kill()
      except OSError:
        pass


PROVIDERS: dict[str, tuple[str, Callable[[], Probe]]] = {
  "claude": ("Claude Code", probe_claude),
  "codex": ("Codex", probe_codex),
}


def merge_probe(
  provider_id: str,
  provider_name: str,
  probe: Probe,
  previous: dict[str, Any] | None,
  now: dt.datetime,
) -> dict[str, Any]:
  old = previous if isinstance(previous, dict) else {}
  if probe.ok:
    limits = open_limits(probe.limits, now)
    last_success = isoformat(now)
    last_success_ms = epoch_ms(now)
  else:
    limits = open_limits(old.get("limits"), now)
    last_success = str(old.get("lastSuccessAt") or "")
    last_success_ms = int(number(old.get("lastSuccessAtMs"))) or epoch_ms(parse_time(last_success))
  return {
    "id": provider_id,
    "name": provider_name,
    "tierLabel": probe.tier_label or str(old.get("tierLabel") or ""),
    "probeOk": probe.ok,
    "lastAttemptAt": isoformat(now),
    "lastAttemptAtMs": epoch_ms(now),
    "lastSuccessAt": last_success,
    "lastSuccessAtMs": last_success_ms,
    "statusText": probe.status_text,
    "helpText": probe.help_text,
    "limits": limits,
  }


def state_path(override: str = "") -> Path:
  chosen = override or os.environ.get("AI_USAGE_STATE_FILE") or ""
  if chosen:
    return Path(os.path.expanduser(os.path.expandvars(chosen)))
  state_home = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
  return state_home / "sab" / "ai-usage" / "state.json"


def read_state(path: Path) -> dict[str, Any]:
  try:
    payload = json.loads(path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return {}
  return payload if isinstance(payload, dict) else {}


def write_state(path: Path, payload: dict[str, Any]) -> None:
  path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
  try:
    path.parent.chmod(0o700)
  except OSError:
    pass
  descriptor, temporary_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
  temporary = Path(temporary_name)
  try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
      json.dump(payload, handle, separators=(",", ":"), sort_keys=True)
      handle.write("\n")
      handle.flush()
      os.fsync(handle.fileno())
    temporary.chmod(0o600)
    temporary.replace(path)
    path.chmod(0o600)
  except BaseException:
    temporary.unlink(missing_ok=True)
    raise


def collect(
  requested: list[str],
  previous_state: dict[str, Any],
  probes: dict[str, Callable[[], Probe]] | None = None,
) -> dict[str, Any]:
  selected = requested or list(PROVIDERS)
  prior = {
    str(record.get("id")): record
    for record in previous_state.get("providers", [])
    if isinstance(record, dict) and record.get("id")
  }
  now = utc_now()
  implementations = probes or {provider_id: definition[1] for provider_id, definition in PROVIDERS.items()}
  results: dict[str, Probe] = {}
  with concurrent.futures.ThreadPoolExecutor(max_workers=len(selected)) as executor:
    futures = {executor.submit(implementations[provider_id]): provider_id for provider_id in selected}
    for future in concurrent.futures.as_completed(futures):
      provider_id = futures[future]
      try:
        results[provider_id] = future.result()
      except Exception:
        results[provider_id] = Probe(False, status_text=f"{PROVIDERS[provider_id][0]} limits unavailable")

  merged: list[dict[str, Any]] = []
  for provider_id in PROVIDERS:
    if provider_id in results:
      name = PROVIDERS[provider_id][0]
      merged.append(merge_probe(provider_id, name, results[provider_id], prior.get(provider_id), now))
    elif provider_id in prior:
      merged.append(prior[provider_id])
  return {
    "schemaVersion": SCHEMA_VERSION,
    "updatedAt": isoformat(now),
    "updatedAtMs": epoch_ms(now),
    "providers": merged,
  }


def parse_args(argv: list[str]) -> argparse.Namespace:
  parser = argparse.ArgumentParser(description="Refresh Claude Code and Codex subscription limit state.")
  parser.add_argument("providers", nargs="*", choices=sorted(PROVIDERS), help="refresh only selected providers")
  parser.add_argument("--state-file", default="", help=argparse.SUPPRESS)
  return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
  args = parse_args(argv or sys.argv[1:])
  destination = state_path(args.state_file)
  destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
  lock_path = destination.with_suffix(destination.suffix + ".lock")
  with lock_path.open("w", encoding="utf-8") as lock:
    try:
      lock_path.chmod(0o600)
    except OSError:
      pass
    fcntl.flock(lock, fcntl.LOCK_EX)
    payload = collect(args.providers, read_state(destination))
    write_state(destination, payload)
  print(json.dumps(payload, separators=(",", ":"), sort_keys=True))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
