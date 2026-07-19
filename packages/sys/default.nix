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
      $PROGRAM help
          Show this text.

  The flake defaults to SYS_FLAKE or the nearest flake.nix in the current
  directory hierarchy. rebuild and test also accept an explicit flake reference.
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
    help|-h|--help) cmd_usage ;;
    *) fail "unknown command: $COMMAND" ;;
  esac
''
