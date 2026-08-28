
usage() {
  cat <<EOF
$APP-requeue — drop oversized items from the $APP queue and let $APP grab a
smaller release instead.

  $APP-requeue [--max-gb N] [--apply] [--no-blocklist]

  --max-gb N      size threshold in GiB (default: $DEFAULT_MAX_GB)
  --apply         actually remove them; without it this only lists
  --no-blocklist  do not blocklist the removed releases — note that $APP
                  then does NOT search for a replacement, so the item is
                  simply dropped

Reads the API key from $CONFIG_XML, so it must run as root.
EOF
}

max_gb="$DEFAULT_MAX_GB"
apply=0
blocklist=true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --max-gb)
      if [ "$#" -lt 2 ]; then echo "--max-gb needs a value" >&2; exit 2; fi
      max_gb="$2"
      shift 2
      ;;
    --apply)
      apply=1
      shift
      ;;
    --no-blocklist)
      blocklist=false
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ ! -r "$CONFIG_XML" ]; then
  echo "cannot read $CONFIG_XML — run as root" >&2
  exit 1
fi
key=$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' "$CONFIG_XML")
if [ -z "$key" ]; then
  echo "no <ApiKey> in $CONFIG_XML" >&2
  exit 1
fi

limit=$(awk -v g="$max_gb" 'BEGIN { printf "%d", g * 1024 * 1024 * 1024 }')

queue=$(curl -sfS -H "X-Api-Key: $key" \
  "$API/queue?page=1&pageSize=1000&$QUEUE_PARAMS")

# One release can occupy several queue records (a sonarr season pack shows
# up once per episode, each carrying the pack's full size) — collapse them,
# the bulk delete is per download anyway.
oversized=$(jq -c --argjson lim "$limit" \
  '[.records[] | select((.size // 0) > $lim)] | unique_by(.downloadId // "id:\(.id)")' \
  <<<"$queue")
count=$(jq -r 'length' <<<"$oversized")

if [ "$count" -eq 0 ]; then
  echo "$APP queue: nothing over $max_gb GiB"
  exit 0
fi

jq -r '.[] | "  \(.size / 1073741824 | . * 10 | round / 10) GiB  \(.quality.quality.name // "?")  \(.title)"' \
  <<<"$oversized"

if [ "$apply" -eq 0 ]; then
  echo
  echo "$count item(s) over $max_gb GiB — re-run with --apply to remove them"
  echo "and have $APP search for a release under the size cap."
  exit 0
fi

body=$(jq -c '{ids: [.[].id]}' <<<"$oversized")

# blocklist=true marks the download failed, which both bars the release
# from ever being re-grabbed and (with skipRedownload=false) fires an
# immediate replacement search — now bounded by Settings -> Indexers ->
# Maximum Size.
curl -sfS -o /dev/null -X DELETE \
  -H "X-Api-Key: $key" -H "Content-Type: application/json" \
  -d "$body" \
  "$API/queue/bulk?removeFromClient=true&blocklist=$blocklist&skipRedownload=false"

echo
if [ "$blocklist" = true ]; then
  echo "removed $count item(s); $APP is searching for smaller replacements"
else
  echo "removed $count item(s); no replacement search (blocklisting skipped)"
fi
