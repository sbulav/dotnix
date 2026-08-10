#!/usr/bin/env bash
# Claude Code status line. Input schema: https://code.claude.com/docs/en/statusline
#
# Renders one line:
#   Opus 5<bolt>:high @agent | herdr-mobile main*3^1 #42 | <bar> 18% | 5h 73% ~2h11m | 7d 41% | $0.42
#
# Box-drawing/arrow glyphs are written as hex escapes so this file stays
# pure ASCII -- literal UTF-8 here has been corrupted by tooling before.
set -u

input=$(cat)

# Defaults first: if jq is missing or the payload is unparseable the eval below
# yields nothing, and under `set -u` the script would die and blank the whole
# status line. With these we still render a usable (if sparse) line.
MODEL=claude DIR="" SESSION=nosession PCT=0
RL5=-1 RL5_AT=0 RL7=-1 RL7_AT=0
COST_CENTS=0 AGENT="" WT="" PR="" EFFORT="" FAST=0

# One jq call for every field. @sh quotes the *value* only, so each line stays
# a real shell assignment after eval (quoting the whole "K=V" would not).
eval "$(jq -r '[
  "MODEL=\(.model.display_name // "claude" | @sh)",
  "DIR=\(.workspace.current_dir // .cwd // "" | @sh)",
  "SESSION=\(.session_id // "nosession" | @sh)",
  "PCT=\((.context_window.used_percentage // 0) | floor)",
  "RL5=\((.rate_limits.five_hour.used_percentage // -1) | floor)",
  "RL5_AT=\((.rate_limits.five_hour.resets_at // 0) | floor)",
  "RL7=\((.rate_limits.seven_day.used_percentage // -1) | floor)",
  "RL7_AT=\((.rate_limits.seven_day.resets_at // 0) | floor)",
  "COST_CENTS=\((((.cost.total_cost_usd // 0) | tonumber? // 0) * 100) | round)",
  "AGENT=\(.agent.name // "" | @sh)",
  "WT=\(.worktree.name // "" | @sh)",
  "PR=\(.pr.number // "" | tostring | @sh)",
  "EFFORT=\(.effort.level // "" | @sh)",
  "FAST=\(if .fast_mode then 1 else 0 end)"
] | join("\n")' <<<"$input" 2>/dev/null)"

NOW=$(date +%s)

RESET=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'

G_FULL=$'\xe2\x96\x93'  # U+2593 dark shade
G_EMPTY=$'\xe2\x96\x91' # U+2591 light shade
G_SEP=$'\xe2\x94\x82'   # U+2502 box vertical
G_BOLT=$'\xe2\x9a\xa1'  # U+26A1 high voltage (fast mode)
G_UP=$'\xe2\x86\x91'    # U+2191 ahead of upstream
G_DOWN=$'\xe2\x86\x93'  # U+2193 behind upstream
G_CLOCK=$'\xe2\x86\xbb' # U+21BB open circle arrow (rate-limit reset)

# green < 70%, yellow 70-89%, red 90%+
heat() {
  if [ "$1" -ge 90 ]; then
    printf '%s' "$RED"
  elif [ "$1" -ge 70 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

bar() { # bar PCT WIDTH
  local filled=$(($1 * $2 / 100)) empty out=""
  [ "$filled" -gt "$2" ] && filled=$2
  [ "$filled" -lt 0 ] && filled=0
  empty=$(($2 - filled))
  while [ "$filled" -gt 0 ]; do
    out+="$G_FULL"
    filled=$((filled - 1))
  done
  while [ "$empty" -gt 0 ]; do
    out+="$G_EMPTY"
    empty=$((empty - 1))
  done
  printf '%s' "$out"
}

eta() { # eta EPOCH -> "1h05m" / "42m" / "now"
  local left=$(($1 - NOW))
  if [ "$left" -le 0 ]; then
    printf 'now'
  elif [ "$left" -ge 3600 ]; then
    printf '%dh%02dm' $((left / 3600)) $((left % 3600 / 60))
  else
    printf '%dm' $((left / 60))
  fi
}

# --- git, cached 5s per session ------------------------------------------------
# The status line re-renders constantly; `git status` on every render lags the
# UI. Cache keyed on session_id (stable per session, unique across concurrent
# sessions) -- $$ changes each invocation and would defeat the cache.
GIT=""
if [ -n "$DIR" ] && [ -d "$DIR" ]; then
  CACHE="${TMPDIR:-/tmp}/cc-statusline-git-$SESSION"
  STALE=1
  if [ -f "$CACHE" ]; then
    MTIME=$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || echo 0)
    [ $((NOW - MTIME)) -lt 5 ] && STALE=0
  fi
  if [ "$STALE" -eq 1 ]; then
    # One `status --branch --porcelain=v2` yields branch, upstream ahead/behind and
    # the dirty entries together -- cheaper than separate symbolic-ref + status +
    # rev-list calls. The "# branch.ab" line is absent when there is no upstream,
    # and branch.head reads "(detached)" off a branch, where we fall back to the
    # short oid.
    git -C "$DIR" status --branch --porcelain=v2 2>/dev/null | awk -F' ' '
      /^# branch\.oid /  { oid = substr($3, 1, 7) }
      /^# branch\.head / { head = $3 }
      /^# branch\.ab /   { ahead = $3 + 0; behind = $4 + 0 }
      !/^#/              { dirty++ }
      END {
        name = (head == "(detached)" || head == "") ? oid : head
        if (behind < 0) behind = -behind
        if (name != "") printf "%s\t%d\t%d\t%d\n", name, dirty + 0, ahead + 0, behind + 0
      }' >"$CACHE" 2>/dev/null
  fi
  if [ -s "$CACHE" ]; then
    IFS=$'\t' read -r B DIRTY AHEAD BEHIND <"$CACHE"
    GIT="$YELLOW$B$RESET"
    [ "${DIRTY:-0}" -gt 0 ] && GIT="$GIT$RED*${DIRTY}$RESET"
    [ "${AHEAD:-0}" -gt 0 ] && GIT="$GIT$CYAN$G_UP${AHEAD}$RESET"
    [ "${BEHIND:-0}" -gt 0 ] && GIT="$GIT$CYAN$G_DOWN${BEHIND}$RESET"
    [ -n "$PR" ] && GIT="$GIT$DIM #$PR$RESET"
  fi
fi

# --- assemble -----------------------------------------------------------------
parts=()

# model, plus fast mode / non-default effort / active agent
seg="$CYAN$MODEL$RESET"
[ "$FAST" = "1" ] && seg="$seg$YELLOW$G_BOLT$RESET"
case "$EFFORT" in
  "" | medium) ;;
  *) seg="$seg$DIM:$EFFORT$RESET" ;;
esac
[ -n "$AGENT" ] && seg="$seg $MAGENTA@$AGENT$RESET"
parts+=("$seg")

# location: dir basename, worktree, git. Strip a trailing slash before taking the
# basename, else "/" and "/Users/sab/" both collapse to an empty segment.
DIRNAME=${DIR%/}
DIRNAME=${DIRNAME##*/}
[ -z "$DIRNAME" ] && [ -n "$DIR" ] && DIRNAME="/"
if [ -n "$DIRNAME" ] || [ -n "$WT" ] || [ -n "$GIT" ]; then
  seg="$DIM$DIRNAME$RESET"
  [ -n "$WT" ] && seg="$seg$MAGENTA wt:$WT$RESET"
  [ -n "$GIT" ] && seg="$seg $GIT"
  parts+=("$seg")
fi

# context window
parts+=("$(heat "$PCT")$(bar "$PCT" 10)$RESET ${PCT}%")

# rate limits, with reset countdown once they matter
if [ "$RL5" -ge 0 ]; then
  seg="$(heat "$RL5")5h ${RL5}%$RESET"
  [ "$RL5" -ge 50 ] && [ "$RL5_AT" -gt 0 ] && seg="$seg$DIM $G_CLOCK$(eta "$RL5_AT")$RESET"
  parts+=("$seg")
fi
if [ "$RL7" -ge 0 ]; then
  seg="$(heat "$RL7")7d ${RL7}%$RESET"
  [ "$RL7" -ge 50 ] && [ "$RL7_AT" -gt 0 ] && seg="$seg$DIM $G_CLOCK$(eta "$RL7_AT")$RESET"
  parts+=("$seg")
fi

# Session cost, once it rounds to a visible amount. jq hands us integer cents and
# the split is integer arithmetic on purpose: bash printf '%.2f' honours
# LC_NUMERIC, so in a comma-decimal locale (de_DE, ru_RU, ...) it rejects JSON's
# "0.42" outright and prints a mangled value.
if [ "$COST_CENTS" -gt 0 ] 2>/dev/null; then
  parts+=("$DIM\$$((COST_CENTS / 100)).$(printf '%02d' $((COST_CENTS % 100)))$RESET")
fi

out=""
for p in "${parts[@]}"; do
  [ -z "$p" ] && continue
  [ -n "$out" ] && out="$out$DIM $G_SEP $RESET"
  out="$out$p"
done
printf '%s\n' "$out"
