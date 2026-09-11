{ writeShellScriptBin, ... }:
writeShellScriptBin "sys" ''
  set -euo pipefail

  fail() {
    printf 'sys: %s\n' "$*" >&2
    exit 1
  }

  resolve_flake() {
    if [[ -n "''${1:-}" ]]; then
      printf '%s\n' "$1"
      return
    fi

    if [[ -n "''${SYS_FLAKE:-}" ]]; then
      printf '%s\n' "$SYS_FLAKE"
      return
    fi

    local directory="$PWD"
    while true; do
      if [[ -f "$directory/flake.nix" ]]; then
        printf '%s\n' "$directory"
        return
      fi
      [[ "$directory" == / ]] && break
      directory="''${directory%/*}"
      [[ -n "$directory" ]] || directory=/
    done

    fail "no flake.nix found; run inside a flake, pass a flake reference, or set SYS_FLAKE"
  }

  require_at_most() {
    local maximum="$1"
    shift
    (( $# <= maximum )) || fail "too many arguments"
  }

  cmd_rebuild() {
    require_at_most 1 "$@"
    local flake
    flake="$(resolve_flake "''${1:-}")"
    printf 'Rebuilding system from %s with %s\n' "$flake" "$REBUILD_COMMAND"
    "$REBUILD_COMMAND" switch --flake "$flake"
  }

  cmd_test() {
    require_at_most 1 "$@"
    local flake
    flake="$(resolve_flake "''${1:-}")"
    printf 'Testing system from %s with %s\n' "$flake" "$REBUILD_COMMAND"
    "$REBUILD_COMMAND" test --fast --flake "$flake"
  }

  cmd_update() {
    require_at_most 1 "$@"
    local flake
    flake="$(resolve_flake)"
    if [[ -n "''${1:-}" ]]; then
      printf 'Updating flake input %s in %s\n' "$1" "$flake"
      nix flake update "$1" --flake "$flake"
    else
      printf 'Updating all flake inputs in %s\n' "$flake"
      nix flake update --flake "$flake"
    fi
  }

  cmd_clean() {
    require_at_most 0 "$@"
    printf 'Cleaning and optimizing the Nix store\n'
    nix store optimise --verbose
    nix store gc --verbose
  }

  # Adopt the flake.lock of a cache candidate that beez already built for this
  # host. It only rewrites flake.lock: nothing is built, activated or deployed,
  # and git is never touched.
  cmd_adopt() {
    local apply=0
    local positional=()
    while (( $# > 0 )); do
      case "$1" in
        --apply) apply=1 ;;
        --) shift; positional+=("$@"); break ;;
        -*) fail "unknown option for adopt: $1" ;;
        *) positional+=("$1") ;;
      esac
      shift
    done
    require_at_most 1 "''${positional[@]}"

    local tool
    for tool in curl jq; do
      command -v "$tool" >/dev/null 2>&1 || fail "adopt needs $tool on PATH"
    done

    local flake
    flake="$(resolve_flake "''${positional[0]:-}")"
    [[ -d "$flake" ]] || fail "adopt needs a local checkout; $flake is not a directory"
    [[ -f "$flake/flake.lock" ]] || fail "no flake.lock in $flake"

    local url
    url="''${SYS_CANDIDATE_URL:-http://beez.sbulav.ru:5001/latest}"
    url="''${url%/}"

    local host
    host="$(uname -n)"
    host="''${host%%.*}"

    local work
    work="$(mktemp -d)"
    # The trap fires outside this function, so the path it reads must be global.
    SYS_ADOPT_TMP="$work"
    trap 'if [[ -n "''${SYS_ADOPT_TMP:-}" ]]; then rm -rf "$SYS_ADOPT_TMP"; fi' EXIT

    local fetch=(curl --fail --silent --show-error --location --max-time 60)
    printf 'Candidate source: %s\n' "$url"
    "''${fetch[@]}" --output "$work/status.json" "$url/status.json" \
      || fail "cannot fetch $url/status.json (is the builder publishing?)"
    jq -e . >/dev/null 2>&1 <"$work/status.json" \
      || fail "$url/status.json is not valid JSON"

    local candidate_id source_rev result state
    candidate_id="$(jq -r '.candidate_id // "unknown"' "$work/status.json")"
    source_rev="$(jq -r '.source_rev // "unknown"' "$work/status.json")"
    result="$(jq -r '.result // "unknown"' "$work/status.json")"
    state="$(jq -r --arg h "$host" '.hosts[$h].state // "absent"' "$work/status.json")"

    printf 'Candidate id:     %s\n' "$candidate_id"
    printf 'Source revision:  %s\n' "$source_rev"
    printf 'Candidate result: %s\n' "$result"
    printf 'State for %s: %s\n' "$host" "$state"

    if [[ "$state" != success ]]; then
      printf '\nHost states in this candidate:\n' >&2
      jq -r '.hosts | to_entries[]
             | "  \(.key): \(.value.state)\(if .value.note then " (" + .value.note + ")" else "" end)"' \
        "$work/status.json" >&2 || true
      fail "refusing to adopt: $host is '$state', not 'success' — this candidate has no cached closure for this host"
    fi

    "''${fetch[@]}" --output "$work/flake.lock" "$url/flake.lock" \
      || fail "cannot fetch $url/flake.lock"
    jq -e . >/dev/null 2>&1 <"$work/flake.lock" \
      || fail "$url/flake.lock is not valid JSON"

    printf '\nLock changes (local -> candidate):\n'
    if cmp -s "$flake/flake.lock" "$work/flake.lock"; then
      printf '  none: the local lock already matches the candidate\n'
    else
      local summary
      summary="$(jq -r -n \
        --slurpfile a "$flake/flake.lock" \
        --slurpfile b "$work/flake.lock" '
        def revs:
          .nodes as $n
          | ($n.root.inputs // {})
          | map_values(
              (if type == "array" then .[0] else . end) as $k
              | (($n[$k].locked) // {})
              | (.rev // .narHash // "?"));
        ($a[0] | revs) as $old
        | ($b[0] | revs) as $new
        | ((($old | keys) + ($new | keys)) | unique)[] as $name
        | ($old[$name] // "absent") as $o
        | ($new[$name] // "removed") as $x
        | select($o != $x)
        | "  \($name): \($o[0:12]) -> \($x[0:12])"' 2>/dev/null || true)"
      if [[ -n "$summary" ]]; then
        printf '%s\n' "$summary"
      elif command -v diff >/dev/null 2>&1; then
        diff --unified=0 "$flake/flake.lock" "$work/flake.lock" || true
      else
        printf '  the locks differ but no input revision changed\n'
      fi
    fi

    if command -v git >/dev/null 2>&1 && git -C "$flake" rev-parse --git-dir >/dev/null 2>&1; then
      local head
      head="$(git -C "$flake" rev-parse HEAD 2>/dev/null || true)"
      if [[ -n "$head" && "$head" != "$source_rev" ]]; then
        printf '\nWarning: local HEAD %s differs from the candidate source rev %s.\n' \
          "''${head:0:12}" "''${source_rev:0:12}"
        printf '         The closures were built from the candidate revision; whatever your\n'
        printf '         tree changes on top of it will still be built locally.\n'
      fi
    fi

    if (( apply == 0 )); then
      printf '\nDry run. Re-run with --apply to replace %s/flake.lock.\n' "$flake"
      return 0
    fi

    cp -f "$work/flake.lock" "$flake/flake.lock" || fail "could not write $flake/flake.lock"
    chmod u+w "$flake/flake.lock" 2>/dev/null || true
    printf '\nAdopted candidate %s into %s/flake.lock\n' "$candidate_id" "$flake"
    printf 'Nothing was built, activated or deployed, and git was not touched.\n'
    printf 'Next: %s rebuild %s\n' "$PROGRAM" "$flake"
    printf 'Do not run "%s update" first: a fresh lock throws this candidate away.\n' "$PROGRAM"
  }

  cmd_usage() {
    cat <<-_EOF
  Usage:
      $PROGRAM rebuild [flake]
          Rebuild and switch the system configuration.
      $PROGRAM test [flake]
          Build and activate the configuration ephemerally.
      $PROGRAM update [input]
          Update all inputs or only the named input.
      $PROGRAM clean
          Garbage collect and optimize the Nix store.
      $PROGRAM adopt [--apply] [flake]
          Show the flake.lock of the published cache candidate that was built
          successfully for this host, and with --apply replace the local
          flake.lock with it. Never builds, activates or deploys.
      $PROGRAM help
          Show this text.

  The flake defaults to SYS_FLAKE or the nearest flake.nix in the current
  directory hierarchy. rebuild, test and adopt also accept an explicit flake
  reference. adopt reads SYS_CANDIDATE_URL (default
  http://beez.sbulav.ru:5001/latest).
  _EOF
  }

  case "$OSTYPE" in
    linux*) REBUILD_COMMAND=nixos-rebuild ;;
    darwin*) REBUILD_COMMAND=darwin-rebuild ;;
    *) fail "unsupported operating system: $OSTYPE" ;;
  esac

  PROGRAM=sys
  COMMAND="''${1:-help}"
  (( $# == 0 )) || shift
  case "$COMMAND" in
    rebuild|r) cmd_rebuild "$@" ;;
    test|t) cmd_test "$@" ;;
    update|u) cmd_update "$@" ;;
    clean|c) cmd_clean "$@" ;;
    adopt) cmd_adopt "$@" ;;
    help|-h|--help) cmd_usage ;;
    *) fail "unknown command: $COMMAND" ;;
  esac
''
