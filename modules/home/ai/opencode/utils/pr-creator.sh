#!/usr/bin/env bash
set -euo pipefail

# --- usage & args ---
usage() {
  cat <<'USAGE'
Usage: pr-creator.sh --host HOST --owner OWNER --repo REPO --base BASE --head HEAD --title TITLE --body BODY
Env:
  FJ_TOKEN   Forgejo API token (required)
USAGE
}

# Parse args
HOST="" OWNER="" REPO="" BASE="" HEAD="" TITLE="" BODY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --owner) OWNER="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --base) BASE="$2"; shift 2;;
    --head) HEAD="$2"; shift 2;;
    --title) TITLE="$2"; shift 2;;
    --body) BODY="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "${FJ_TOKEN:-}" ]]; then
  echo "Ошибка: переменная FJ_TOKEN не задана." >&2
  exit 1
fi

for v in HOST OWNER REPO BASE HEAD TITLE BODY; do
  if [[ -z "${!v}" ]]; then
    echo "Ошибка: $v пуст." >&2
    usage
    exit 2
  fi
done

# Escape newlines and quotes for JSON safely
json_escape() {
  python3 - <<'PY' "$@"
import json,sys
print(json.dumps(sys.argv[1]))
PY
}

TITLE_JSON=$(json_escape "$TITLE")
BODY_JSON=$(json_escape "$BODY")

API="https://${HOST}/api/v1/repos/${OWNER}/${REPO}/pulls"

# Compose payload (head is source branch, base is target/default branch)
PAYLOAD=$(cat <<EOF
{
  "head": "${HEAD}",
  "base": "${BASE}",
  "title": ${TITLE_JSON},
  "body": ${BODY_JSON}
}
EOF
)

# Run curl
set -x
curl -sS -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: token ${FJ_TOKEN}" \
  "${API}" \
  -d "${PAYLOAD}"
set +x
