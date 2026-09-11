{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
# Advance cache builder.
#
# Every run freezes a *candidate*: the git revision the sync service checked
# out plus the exact flake.lock that `nix flake update` produced, copied out of
# the working tree into an immutable directory. Every host is then built from
# that frozen copy, so a concurrent sync cannot change the inputs mid-run, and
# the lock that was actually built is published for local machines to adopt
# deliberately (`sys adopt`). Nothing here updates, switches or deploys a local
# machine.
#
# The run is bounded twice over: `perHostTimeout` per host and `totalBudget`
# for the whole batch. The summary and the notification live in a separate
# report script wired to `ExecStopPost=`, so a timeout, a SIGTERM or a
# preparation failure still reports instead of dying silently as the
# 2026-09-10 run did.
with lib;
with lib.custom;
let
  cfg = config.${namespace}.services.nix-cache-builder;

  hostName = config.networking.hostName;

  # Explicit substituter list for build commands. `--substituters`
  # REPLACES the resolved list, so this bypasses the Determinate-injected
  # `install.determinate.systems` / `cache.flakehub.com` caches, which time
  # out (<1 B/s) and 401 from this network and otherwise poison every build.
  buildSubstituters = "https://cache.nixos.org";

  candidatesDir = "${cfg.stateDir}/candidates";
  sourcesDir = "${cfg.stateDir}/sources";
  currentCandidateFile = "${cfg.stateDir}/current-candidate";
  # Written by the reporter, read by the OnFailure= handler so a run the
  # reporter already described does not produce a second notification.
  reportStampFile = "${cfg.stateDir}/.last-reported-invocation";

  signingKeyPath = config.sops.secrets."nix-cache-priv-key".path;

  notifyEnabled = cfg.telegram.enable || cfg.email.enable;

  deliverScript = lib.${namespace}.notifications.mkDeliverScript pkgs {
    inherit hostName;
    telegram = {
      inherit (cfg.telegram) enable chatId proxyUrl;
    };
    email = {
      inherit (cfg.email) enable recipient;
      fromName = "${hostName} nix cache builder";
    };
  };
  # Only referenced from `optionalString notifyEnabled` blocks: with both
  # channels disabled mkDeliverScript refuses to build, and it must not be
  # forced then.
  deliver = "${deliverScript}/bin/notify-deliver";
  # The leading dash keeps a missing token file from failing the unit: the
  # deliverer then falls back to email instead of sending nothing.
  telegramEnv = optionalAttrs cfg.telegram.enable {
    EnvironmentFile = "-${config.sops.secrets."telegram-notifications-bot-token".path}";
  };

  # Durations are systemd-flavoured strings ("4h", "90m", "1h30m"). They are
  # parsed in the shell because both `timeout` and the budget arithmetic need
  # seconds; the option values are checked by an assertion below.
  durationPattern = "([0-9]+(d|h|m|s)?)+";
  durationHelpers = ''
    to_seconds() {
      local spec="$1" rest="$1" total=0 num unit
      if [ -z "$rest" ]; then
        printf 'invalid duration: %s\n' "$spec" >&2
        return 1
      fi
      while [ -n "$rest" ]; do
        if [[ "$rest" =~ ^([0-9]+)(d|h|m|s|)(.*)$ ]]; then
          num="''${BASH_REMATCH[1]}"
          unit="''${BASH_REMATCH[2]}"
          rest="''${BASH_REMATCH[3]}"
          case "$unit" in
            d) total=$((total + num * 86400)) ;;
            h) total=$((total + num * 3600)) ;;
            m) total=$((total + num * 60)) ;;
            *) total=$((total + num)) ;;
          esac
        else
          printf 'invalid duration: %s\n' "$spec" >&2
          return 1
        fi
      done
      printf '%s\n' "$total"
    }

    fmt_duration() {
      local s="$1"
      printf '%dh%02dm%02ds' "$((s / 3600))" "$(((s % 3600) / 60))" "$((s % 60))"
    }
  '';

  # Where everything lives. Each script declares only the paths it uses, so
  # shellcheck's unused-variable check keeps working.
  pathValues = {
    flake_dir = escapeShellArg cfg.flakePath;
    cache_dir = escapeShellArg cfg.cacheDir;
    candidates_dir = escapeShellArg candidatesDir;
    sources_dir = escapeShellArg sourcesDir;
    current_file = escapeShellArg currentCandidateFile;
  };
  mkPrologue =
    {
      paths ? [ ],
      withHosts ? false,
    }:
    concatStringsSep "\n" (
      (map (name: "${name}=${pathValues.${name}}") paths)
      ++ optional withHosts "hosts=(${escapeShellArgs cfg.hosts})"
    );

  # A candidate id is <UTC timestamp>-<first 12 hex of sha256(flake.lock)>, so
  # a plain lexicographic sort is chronological everywhere below.
  candidateIdGlob = "[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-*";

  # ---------------------------------------------------------------------------
  # Build script: prepare a candidate, then build each host from the frozen
  # copy, recording the outcome the moment the host finishes.
  # ---------------------------------------------------------------------------
  buildScript = pkgs.writeShellApplication {
    name = "nix-cache-build";
    # SC2016: jq filters are single-quoted on purpose — `$h`, `$state` and
    # friends are jq variables bound with --arg, not shell variables.
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = with pkgs; [
      coreutils
      git
      gnutar
      jq
      nix
    ];
    text = ''
      ${mkPrologue {
        paths = [
          "flake_dir"
          "cache_dir"
          "candidates_dir"
          "sources_dir"
          "current_file"
        ];
        withHosts = true;
      }}
      ${durationHelpers}

      builder_host=${escapeShellArg hostName}
      started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      run_start=$(date +%s)
      per_host_timeout=$(to_seconds ${escapeShellArg cfg.perHostTimeout})
      total_budget=$(to_seconds ${escapeShellArg cfg.totalBudget})
      # Never start a host with less than this left: it could only be killed.
      min_slice=300

      mkdir -p "$cache_dir" "$candidates_dir" "$sources_dir"
      chmod 0755 "$candidates_dir"

      # Provisional id: a preparation failure before the lock is readable still
      # has to produce a candidate directory for the reporter.
      candidate_id="$(date -u +%Y%m%dT%H%M%SZ)-unknown"
      cand_dir=""
      status_file=""
      input_update=disabled
      # A degraded (but survivable) preparation, e.g. `nix flake update` failed
      # and the committed lock was restored. The run continues; its best
      # possible result is "partial".
      prepare_degraded=false
      source_rev=unknown
      lock_sha=unknown

      publish_candidate_id() {
        printf '%s\n' "$candidate_id" >"$current_file"
        chmod 0644 "$current_file"
      }

      # Atomic status update: jq filter first, then its --arg options.
      update_status() {
        local filter="$1"
        shift
        local tmp
        [ -n "$status_file" ] || return 0
        tmp=$(mktemp "$cand_dir/.status.XXXXXX")
        if jq "$@" "$filter" "$status_file" >"$tmp"; then
          chmod 0644 "$tmp"
          mv -f "$tmp" "$status_file"
        else
          rm -f "$tmp"
          printf 'warning: could not update %s\n' "$status_file" >&2
        fi
      }

      fail_prepare() {
        local reason="$1"
        printf '✗ preparation failed: %s\n' "$reason" >&2
        cand_dir="$candidates_dir/$candidate_id"
        status_file="$cand_dir/status.json"
        mkdir -p "$cand_dir"
        chmod 0755 "$cand_dir"
        if jq -n \
          --arg candidate_id "$candidate_id" \
          --arg source_rev "$source_rev" \
          --arg lock_sha256 "$lock_sha" \
          --arg started_at "$started_at" \
          --arg builder_host "$builder_host" \
          --arg input_update "$input_update" \
          --arg prepare_error "$reason" \
          '{candidate_id: $candidate_id, source_rev: $source_rev,
            lock_sha256: $lock_sha256, started_at: $started_at,
            finished_at: null, result: "prepare-failed",
            builder_host: $builder_host, input_update: $input_update,
            prepare_degraded: true, prepare_error: $prepare_error,
            hosts: {}}' >"$status_file.tmp"; then
          chmod 0644 "$status_file.tmp"
          mv -f "$status_file.tmp" "$status_file"
        else
          rm -f "$status_file.tmp"
        fi
        publish_candidate_id
        exit 1
      }

      # --- Prepare ------------------------------------------------------------
      [ -d "$flake_dir/.git" ] || fail_prepare "no git checkout at $flake_dir"
      cd "$flake_dir"
      source_rev=$(git rev-parse HEAD) || fail_prepare "cannot read HEAD in $flake_dir"

      build_args=()
      ${optionalString (cfg.remoteBuilderDisableFile != null) ''
        if [ -e ${escapeShellArg cfg.remoteBuilderDisableFile} ]; then
          build_args+=(--builders "")
          echo "Remote builders disabled by ${cfg.remoteBuilderDisableFile}; using $builder_host only"
        else
          echo "Remote builder configuration: $(nix config show builders 2>/dev/null || echo unavailable)"
        fi
      ''}

      ${optionalString cfg.updateFlake ''
        echo "Updating flake inputs..."
        if nix flake update; then
          input_update=updated
          echo "✓ Flake inputs updated"
        else
          git restore --source=HEAD -- flake.lock || true
          input_update="failed; using source lock"
          prepare_degraded=true
          echo "⚠ Failed to update flake inputs; building the committed source lock" >&2
        fi
      ''}

      [ -f flake.lock ] || fail_prepare "flake.lock is missing in $flake_dir"
      lock_sha=$(sha256sum flake.lock | cut -d' ' -f1)
      candidate_id="$(date -u +%Y%m%dT%H%M%SZ)-''${lock_sha:0:12}"
      src_dir="$sources_dir/$candidate_id"
      cand_dir="$candidates_dir/$candidate_id"
      status_file="$cand_dir/status.json"

      # Freeze the source. `git archive` of HEAD plus the updated lock is
      # exactly what will be built; the sync service may reset the checkout
      # underneath us at any time after this point without any effect.
      rm -rf "$src_dir"
      mkdir -p "$src_dir"
      git archive --format=tar HEAD | tar -x -C "$src_dir" \
        || fail_prepare "could not archive $source_rev into $src_dir"
      cp -f flake.lock "$src_dir/flake.lock" \
        || fail_prepare "could not copy the candidate lock into $src_dir"

      # Published metadata. Only these files live in the candidate directory:
      # the source tree stays in $sources_dir, which the publisher never serves.
      mkdir -p "$cand_dir"
      chmod 0755 "$cand_dir"
      cp -f flake.lock "$cand_dir/flake.lock" || fail_prepare "could not publish the candidate lock"
      chmod 0644 "$cand_dir/flake.lock"

      jq -n \
        --arg candidate_id "$candidate_id" \
        --arg source_rev "$source_rev" \
        --arg lock_sha256 "$lock_sha" \
        --arg flake_repo ${escapeShellArg cfg.flakeRepo} \
        --arg flake_branch ${escapeShellArg cfg.flakeBranch} \
        --arg started_at "$started_at" \
        --arg builder_host "$builder_host" \
        '{candidate_id: $candidate_id, source_rev: $source_rev,
          lock_sha256: $lock_sha256, flake_repo: $flake_repo,
          flake_branch: $flake_branch, started_at: $started_at,
          builder_host: $builder_host}' >"$cand_dir/metadata.json" \
        || fail_prepare "could not write metadata.json"
      chmod 0644 "$cand_dir/metadata.json"

      # input name -> the `locked` object the build actually resolved.
      jq '.nodes as $nodes
          | $nodes.root.inputs
          | map_values((if type == "array" then .[0] else . end) as $node | $nodes[$node].locked)' \
        flake.lock >"$cand_dir/inputs.json" \
        || fail_prepare "could not derive inputs.json from flake.lock"
      chmod 0644 "$cand_dir/inputs.json"

      hosts_json=$(jq -n '$ARGS.positional | map({key: ., value: {state: "pending"}}) | from_entries' \
        --args "''${hosts[@]}")
      jq -n \
        --arg candidate_id "$candidate_id" \
        --arg source_rev "$source_rev" \
        --arg lock_sha256 "$lock_sha" \
        --arg started_at "$started_at" \
        --arg builder_host "$builder_host" \
        --arg input_update "$input_update" \
        --argjson prepare_degraded "$prepare_degraded" \
        --argjson hosts "$hosts_json" \
        '{candidate_id: $candidate_id, source_rev: $source_rev,
          lock_sha256: $lock_sha256, started_at: $started_at, finished_at: null,
          result: "running", builder_host: $builder_host,
          input_update: $input_update, prepare_degraded: $prepare_degraded,
          hosts: $hosts}' >"$status_file" \
        || fail_prepare "could not write status.json"
      chmod 0644 "$status_file"

      publish_candidate_id
      ln -sfn "$candidate_id" "$candidates_dir/latest"

      echo "=== Candidate ==="
      echo "Candidate id:    $candidate_id"
      echo "Source revision: $source_rev"
      echo "Input update:    $input_update"
      echo "Lock SHA-256:    $lock_sha"
      echo "Frozen source:   $src_dir"
      echo "Per-host timeout: $(fmt_duration "$per_host_timeout")"
      echo "Total budget:     $(fmt_duration "$total_budget")"
      echo "Build order:     ''${hosts[*]}"
      echo "================="

      # --- Build --------------------------------------------------------------
      success_count=0
      budget_exhausted=0

      for host in "''${hosts[@]}"; do
        if [ "$budget_exhausted" -eq 1 ]; then
          update_status '.hosts[$h] = {state: "skipped-budget"}' --arg h "$host"
          echo "⏭ Skipping $host: the total budget is exhausted" >&2
          continue
        fi

        elapsed=$(( $(date +%s) - run_start ))
        remaining=$((total_budget - elapsed))
        if [ "$remaining" -lt "$min_slice" ]; then
          budget_exhausted=1
          update_status '.hosts[$h] = {state: "skipped-budget"}' --arg h "$host"
          echo "⏭ Skipping $host: $(fmt_duration "$elapsed") elapsed of $(fmt_duration "$total_budget")" >&2
          continue
        fi

        # Clamp to what is left of the budget so the batch cannot outlive
        # TimeoutStartSec and be killed by systemd instead of by this loop.
        slice=$((remaining < per_host_timeout ? remaining : per_host_timeout))

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Building $host (limit $(fmt_duration "$slice"))"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        host_started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        host_start=$(date +%s)
        update_status '.hosts[$h] = {state: "running", started_at: $t}' \
          --arg h "$host" --arg t "$host_started"

        out_link="$cache_dir/$host-result-$candidate_id"
        rm -f "$out_link"

        rc=0
        timeout --signal=TERM --kill-after=1m "''${slice}s" \
          nix build \
          --out-link "$out_link" \
          "path:$src_dir#nixosConfigurations.$host.config.system.build.toplevel" \
          --substituters ${escapeShellArg buildSubstituters} \
          --max-jobs ${toString cfg.maxJobs} \
          --cores ${toString cfg.buildCores} \
          --print-build-logs \
          --keep-going \
          "''${build_args[@]}" || rc=$?

        host_end=$(date +%s)
        duration=$((host_end - host_start))
        state=failed
        note=""
        store_path=""
        closure_bytes=null

        if [ "$rc" -eq 0 ]; then
          if nix store sign --recursive --key-file ${escapeShellArg signingKeyPath} "$out_link"; then
            store_path=$(readlink -f "$out_link")
            closure_bytes=$(nix path-info -S --json "$store_path" \
              | jq '[.[] | .closureSize] | add' 2>/dev/null) || closure_bytes=null
            [ -n "$closure_bytes" ] || closure_bytes=null
            # Relative target: the stable name and the generation live in the
            # same directory, so the pair survives a bind mount or a move.
            ln -sfn "$host-result-$candidate_id" "$cache_dir/$host-result"
            state=success
            success_count=$((success_count + 1))
            echo "✓ $host: signed and published in ''${duration}s"
          else
            note="signing failed"
            rm -f "$out_link"
            echo "✗ $host: signing failed; previous generations preserved" >&2
          fi
        elif [ "$rc" -eq 124 ] || { [ "$rc" -eq 137 ] && [ "$duration" -ge "$slice" ]; }; then
          # 124: killed by SIGTERM at the deadline. 137: it ignored SIGTERM and
          # `--kill-after` had to SIGKILL it, which is only a timeout if the
          # deadline had in fact passed (otherwise it is an OOM kill).
          state=timeout
          note="no result after $(fmt_duration "$slice")"
          rm -f "$out_link"
          echo "⏱ $host: timed out after $(fmt_duration "$slice"); previous generations preserved" >&2
        else
          note="nix build exited $rc"
          rm -f "$out_link"
          echo "✗ $host: build failed (exit $rc); previous generations preserved" >&2
        fi

        update_status \
          '.hosts[$h] = ({state: $state, started_at: $t, duration_s: ($d | tonumber)}
             + (if $store_path == "" then {} else {store_path: $store_path} end)
             + (if $closure == null then {} else {closure_bytes: $closure} end)
             + (if $note == "" then {} else {note: $note} end))' \
          --arg h "$host" \
          --arg state "$state" \
          --arg t "$host_started" \
          --arg d "$duration" \
          --arg store_path "$store_path" \
          --argjson closure "$closure_bytes" \
          --arg note "$note"
      done

      echo ""
      echo "Hosts succeeded: $success_count of ''${#hosts[@]}"
      echo "Total elapsed:   $(fmt_duration "$(( $(date +%s) - run_start ))")"
      echo "The summary and the notification are produced by the report step."

      # Only a batch in which nothing at all succeeded is a unit failure; a
      # partial run keeps every result it did produce.
      if [ "$success_count" -eq 0 ]; then
        exit 1
      fi
    '';
  };

  # ---------------------------------------------------------------------------
  # Report script: ExecStopPost=. Runs on success, failure, SIGTERM and
  # start-timeout alike, so the run is always described somewhere.
  # ---------------------------------------------------------------------------
  reportScript = pkgs.writeShellApplication {
    name = "nix-cache-report";
    # SC2016: see buildScript — single-quoted jq filters, jq variables.
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = ''
      ${mkPrologue {
        paths = [
          "candidates_dir"
          "current_file"
        ];
      }}

      now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      unit_result="''${SERVICE_RESULT:-unknown}"
      exit_status="''${EXIT_STATUS:-unknown}"

      candidate=""
      if [ -r "$current_file" ]; then
        candidate=$(head -n1 "$current_file" || true)
      fi
      cand_dir="$candidates_dir/$candidate"
      status_file="$cand_dir/status.json"

      message_file=$(mktemp)
      # shellcheck disable=SC2329
      cleanup() { rm -f "$message_file"; }
      trap cleanup EXIT
      trap 'exit 143' TERM INT

      if [ -z "$candidate" ] || [ ! -r "$status_file" ]; then
        result=prepare-failed
        {
          printf '%s\n' "🔥 ${hostName} | Nix cache candidate: NO CANDIDATE"
          printf 'no candidate: preparation failed before a status file was written\n'
          printf 'Unit result: %s (exit status %s)\n' "$unit_result" "$exit_status"
          printf 'Inspect: journalctl -u nix-cache-builder.service -n 200\n'
        } >"$message_file"
      else
        # Anything still pending or running when the unit stopped was
        # interrupted: a timeout, a SIGTERM or a crash of the build script.
        tmp=$(mktemp "$cand_dir/.status.XXXXXX")
        if jq --arg finished "$now_iso" '
              .hosts |= with_entries(
                .value.state |= (if . == "pending" or . == "running" then "interrupted" else . end))
              | .finished_at = $finished
              | .result = (
                  if .result == "prepare-failed" then "prepare-failed"
                  else
                    ([.hosts[].state]) as $states
                    | if ($states | map(select(. == "success")) | length) == 0 then "failed"
                      elif ($states | all(. == "success")) and ((.prepare_degraded // false) | not) then "success"
                      else "partial"
                      end
                  end)
            ' "$status_file" >"$tmp"; then
          chmod 0644 "$tmp"
          mv -f "$tmp" "$status_file"
        else
          rm -f "$tmp"
          printf 'warning: could not finalise %s\n' "$status_file" >&2
        fi

        result=$(jq -r '.result // "unknown"' "$status_file")
        case "$result" in
          success) icon="✅" ;;
          partial) icon="⚠️" ;;
          *) icon="🔥" ;;
        esac

        {
          printf '%s %s | Nix cache candidate: %s\n' "$icon" ${escapeShellArg hostName} \
            "$(printf '%s' "$result" | tr '[:lower:]' '[:upper:]')"
          jq -r '
            def human(b): if (b | type) != "number" then "?"
              else (((b / 1073741824) * 10 | round) / 10 | tostring) + " GiB" end;
            def icon(s): if s == "success" then "✅"
              elif s == "failed" then "❌"
              elif s == "timeout" then "⏱"
              elif s == "skipped-budget" then "⏭"
              elif s == "interrupted" then "⚠️"
              else "•" end;
            "Candidate: \(.candidate_id)",
            "Source rev: \((.source_rev // "unknown")[0:12])",
            "Lock: \((.lock_sha256 // "unknown")[0:12])",
            "Inputs: \(.input_update // "unknown")",
            "Window: \(.started_at // "?") → \(.finished_at // "?")",
            (if .prepare_error then "Preparation error: \(.prepare_error)" else empty end),
            "==========",
            (.hosts | to_entries[]
              | "\(icon(.value.state)) \(.key): \(.value.state)"
                + (if (.value.duration_s | type) == "number" then " in \(.value.duration_s)s" else "" end)
                + (if (.value.closure_bytes | type) == "number" then " (\(human(.value.closure_bytes)))" else "" end)
                + (if .value.note then " – \(.value.note)" else "" end)),
            "=========="
          ' "$status_file"
          printf 'Unit result: %s (exit status %s)\n' "$unit_result" "$exit_status"
          printf 'Free on /nix/store: %s\n' \
            "$(df -B1 --output=avail /nix/store | tail -n1 | tr -dc '0-9' | numfmt --to=iec)"
          ${optionalString cfg.publish.enable ''
            printf 'Candidate: http://%s:%d/%s/\n' ${escapeShellArg hostName} ${toString cfg.publish.port} "$candidate"
            printf 'Adopt on a local machine: sys adopt\n'
          ''}
        } >"$message_file"

        if [ "$result" = success ]; then
          ln -sfn "$candidate" "$candidates_dir/last-success"
        fi
        ln -sfn "$candidate" "$candidates_dir/latest"
      fi

      echo "=== Report ==="
      cat "$message_file"
      echo "=============="

      ${
        if notifyEnabled then
          ''
            case "$result" in
              success)
                should_notify=${if cfg.telegram.notifyOnSuccess then "true" else "false"}
                priority=${cfg.telegram.successPriority}
                ;;
              partial)
                should_notify=${if cfg.telegram.notifyOnPartialSuccess then "true" else "false"}
                priority=${cfg.telegram.failurePriority}
                ;;
              *)
                should_notify=${if cfg.telegram.notifyOnFailure then "true" else "false"}
                priority=${cfg.telegram.failurePriority}
                ;;
            esac

            if [ "$should_notify" = true ]; then
              # A failed delivery must not fail the unit: notify-deliver has
              # already written the whole message to the journal.
              ${deliver} "$message_file" "[${hostName}] nix cache candidate $result" "$priority" \
                || echo "report: notification delivery failed" >&2
            else
              echo "report: notification disabled for result '$result'"
            fi
          ''
        else
          ''
            echo "report: no notification channel is enabled"
          ''
      }

      # Tell the OnFailure= handler that this invocation has been reported.
      if [ -n "''${INVOCATION_ID:-}" ]; then
        printf '%s\n' "$INVOCATION_ID" >${escapeShellArg reportStampFile}
      fi

      exit 0
    '';
  };

  # ---------------------------------------------------------------------------
  # OnFailure= handler: the safety net for a failure the reporter itself could
  # not describe (it crashed, or the unit failed before it ran).
  # ---------------------------------------------------------------------------
  failureScript = pkgs.writeShellApplication {
    name = "nix-cache-notify-failure";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      unit=nix-cache-builder.service
      invocation=$(systemctl show -p InvocationID --value "$unit" 2>/dev/null || true)
      stamp=$(cat ${escapeShellArg reportStampFile} 2>/dev/null || true)
      if [ -n "$invocation" ] && [ "$invocation" = "$stamp" ]; then
        echo "invocation $invocation was already reported by the report step; not notifying twice"
        exit 0
      fi

      message_file=$(mktemp)
      # shellcheck disable=SC2329
      cleanup() { rm -f "$message_file"; }
      trap cleanup EXIT
      trap 'exit 143' TERM INT

      show() { systemctl show -p "$1" --value "$2" 2>/dev/null || echo unknown; }
      result=$(show Result "$unit")
      code=$(show ExecMainCode "$unit")
      status=$(show ExecMainStatus "$unit")

      {
        printf '%s\n' "🔥 ${hostName} | nix-cache-builder failed without a report"
        printf 'Unit: %s\nResult: %s (main process %s, status %s)\n\n' \
          "$unit" "$result" "$code" "$status"
        printf 'Last ${toString cfg.errorLogLines} journal lines:\n'
        if [ -n "$invocation" ] && [ "$invocation" != unknown ]; then
          journalctl _SYSTEMD_INVOCATION_ID="$invocation" -n ${toString cfg.errorLogLines} \
            -o cat --no-pager || true
        else
          journalctl -u "$unit" -n ${toString cfg.errorLogLines} -o cat --no-pager || true
        fi
        printf '\nInspect: journalctl -u %s\n' "$unit"
      } >"$message_file"

      ${optionalString notifyEnabled ''
        ${deliver} "$message_file" "[${hostName}] nix-cache-builder failed" high || true
      ''}
    '';
  };

  # ---------------------------------------------------------------------------
  # Cleanup script: retention by generation count, then by real store pressure.
  # Removing an out-link removes its GC root; the space itself comes back when
  # the weekly `nix.gc` runs. This never collects garbage itself.
  # ---------------------------------------------------------------------------
  cleanupScript = pkgs.writeShellApplication {
    name = "nix-cache-cleanup";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      nix
    ];
    text = ''
      ${mkPrologue {
        paths = [
          "cache_dir"
          "candidates_dir"
          "sources_dir"
          "current_file"
        ];
        withHosts = true;
      }}

      keep_generations=${toString cfg.keepGenerations}
      keep_candidates=${toString cfg.keepCandidates}
      min_free_bytes=$((${toString cfg.minFreeGB} * 1024 * 1024 * 1024))

      free_bytes() {
        df -B1 --output=avail /nix/store | tail -n1 | tr -dc '0-9'
      }

      before=$(free_bytes)
      printf 'Free on /nix/store before: %s\n' "$(numfmt --to=iec "$before")"

      # Generation links that a stable <host>-result symlink points at are
      # never removed: the stable name must never dangle.
      declare -A protected=()
      for host in "''${hosts[@]}"; do
        stable="$cache_dir/$host-result"
        if [ -L "$stable" ]; then
          protected["$(basename "$(readlink "$stable")")"]=1
        fi
      done

      # Oldest first; the candidate id sorts chronologically.
      generations_for() {
        local host="$1" link
        for link in "$cache_dir/$host-result-"*; do
          [ -L "$link" ] || continue
          basename "$link"
        done | sort
      }

      remove_generation() {
        local name="$1"
        if rm -f "$cache_dir/$name"; then
          printf '  removed generation %s\n' "$name"
          return 0
        fi
        printf '  warning: could not remove %s\n' "$name" >&2
        return 1
      }

      # --- 1. Per-host generation count ---------------------------------------
      echo "Trimming to $keep_generations generations per host..."
      for host in "''${hosts[@]}"; do
        mapfile -t gens < <(generations_for "$host")
        count=''${#gens[@]}
        [ "$count" -gt "$keep_generations" ] || continue
        excess=$((count - keep_generations))
        for ((i = 0; i < excess; i++)); do
          # Never the newest, whatever the count says.
          [ "$i" -lt "$((count - 1))" ] || break
          name="''${gens[$i]}"
          if [ -n "''${protected[$name]:-}" ]; then
            printf '  keeping %s (target of %s-result)\n' "$name" "$host"
            continue
          fi
          remove_generation "$name" || true
        done
      done

      # --- 2. Real store pressure ---------------------------------------------
      # Free space does not move until the weekly `nix.gc` collects the
      # released paths, so in practice this drains down to one generation per
      # host in a single pass and then says so.
      while [ "$(free_bytes)" -lt "$min_free_bytes" ]; do
        victim=""
        for host in "''${hosts[@]}"; do
          mapfile -t gens < <(generations_for "$host")
          count=''${#gens[@]}
          [ "$count" -gt 1 ] || continue
          for ((i = 0; i < count - 1; i++)); do
            name="''${gens[$i]}"
            [ -z "''${protected[$name]:-}" ] || continue
            if [ -z "$victim" ] || [[ "''${name#*-result-}" < "''${victim#*-result-}" ]]; then
              victim="$name"
            fi
            break
          done
        done
        if [ -z "$victim" ]; then
          printf 'WARNING: only %s of %s free on /nix/store and one generation per host remains; nothing left to release here\n' \
            "$(numfmt --to=iec "$(free_bytes)")" "$(numfmt --to=iec "$min_free_bytes")" >&2
          break
        fi
        printf 'Store pressure (%s free, want %s): releasing the oldest generation\n' \
          "$(numfmt --to=iec "$(free_bytes)")" "$(numfmt --to=iec "$min_free_bytes")"
        remove_generation "$victim" || break
      done

      # --- 3. Candidate metadata ----------------------------------------------
      current=""
      if [ -r "$current_file" ]; then
        current=$(head -n1 "$current_file" || true)
      fi
      last_success=""
      if [ -L "$candidates_dir/last-success" ]; then
        last_success=$(basename "$(readlink "$candidates_dir/last-success")")
      fi

      mapfile -t candidates < <(
        for dir in "$candidates_dir"/${candidateIdGlob}; do
          [ -d "$dir" ] || continue
          [ -L "$dir" ] && continue
          basename "$dir"
        done | sort
      )
      total=''${#candidates[@]}
      if [ "$total" -gt "$keep_candidates" ]; then
        excess=$((total - keep_candidates))
        echo "Pruning $excess candidate directories beyond $keep_candidates..."
        for ((i = 0; i < excess; i++)); do
          [ "$i" -lt "$((total - 1))" ] || break
          name="''${candidates[$i]}"
          if [ "$name" = "$current" ] || [ "$name" = "$last_success" ]; then
            printf '  keeping candidate %s (current or newest success)\n' "$name"
            continue
          fi
          rm -rf "''${candidates_dir:?}/$name" "''${sources_dir:?}/$name"
          printf '  removed candidate %s\n' "$name"
        done
      fi

      # Source trees whose candidate directory is gone are dead weight.
      for dir in "$sources_dir"/${candidateIdGlob}; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        [ "$name" = "$current" ] && continue
        [ -d "$candidates_dir/$name" ] && continue
        rm -rf "''${sources_dir:?}/$name"
        printf '  removed orphan source tree %s\n' "$name"
      done

      # --- 4. Repair the published symlinks -----------------------------------
      mapfile -t candidates < <(
        for dir in "$candidates_dir"/${candidateIdGlob}; do
          [ -d "$dir" ] || continue
          [ -L "$dir" ] && continue
          basename "$dir"
        done | sort
      )
      if [ "''${#candidates[@]}" -gt 0 ]; then
        ln -sfn "''${candidates[-1]}" "$candidates_dir/latest"
        newest_success=""
        for name in "''${candidates[@]}"; do
          [ -r "$candidates_dir/$name/status.json" ] || continue
          if [ "$(jq -r '.result // ""' "$candidates_dir/$name/status.json")" = success ]; then
            newest_success="$name"
          fi
        done
        if [ -n "$newest_success" ]; then
          ln -sfn "$newest_success" "$candidates_dir/last-success"
        fi
      fi

      # --- 5. What is retained -------------------------------------------------
      echo "Retained results:"
      for host in "''${hosts[@]}"; do
        stable="$cache_dir/$host-result"
        [ -L "$stable" ] || continue
        target=$(readlink -f "$stable" || true)
        if [ -n "$target" ] && [ -e "$target" ]; then
          size=$(nix path-info -S --json "$target" 2>/dev/null \
            | jq -r '[.[] | .closureSize] | add' 2>/dev/null) || size=""
          if [ -n "$size" ] && [ "$size" != null ]; then
            printf '  %s: %s (%s)\n' "$host" "$(numfmt --to=iec "$size")" "$target"
          else
            printf '  %s: %s\n' "$host" "$target"
          fi
        else
          printf '  %s: stable symlink is dangling\n' "$host" >&2
        fi
      done

      printf 'Free on /nix/store after: %s (was %s)\n' \
        "$(numfmt --to=iec "$(free_bytes)")" "$(numfmt --to=iec "$before")"
    '';
  };
in
{
  imports = [
    (mkRemovedOptionModule
      [
        namespace
        "services"
        "nix-cache-builder"
        "maxCacheSize"
      ]
      "Cleanup now watches real store pressure. Use custom.services.nix-cache-builder.minFreeGB (and keepGenerations) instead."
    )
    (mkRemovedOptionModule
      [
        namespace
        "services"
        "nix-cache-builder"
        "cacheServer"
        "priority"
      ]
      "The option was never applied. Set the priority per client in system.nix.cache-servers.<entry>.priority instead."
    )
    (mkRemovedOptionModule
      [
        namespace
        "services"
        "nix-cache-builder"
        "email"
        "notifyOnSuccess"
      ]
      "Delivery is Telegram first, email as the fallback. Gate notifications with custom.services.nix-cache-builder.telegram.notifyOnSuccess."
    )
    (mkRemovedOptionModule
      [
        namespace
        "services"
        "nix-cache-builder"
        "email"
        "notifyOnFailure"
      ]
      "Delivery is Telegram first, email as the fallback. Gate notifications with custom.services.nix-cache-builder.telegram.notifyOnFailure."
    )
    (mkRemovedOptionModule [
      namespace
      "services"
      "nix-cache-builder"
      "email"
      "sendOnTelegramFailure"
    ] "Email is always the fallback when Telegram delivery fails; the toggle no longer exists.")
  ];

  options.${namespace}.services.nix-cache-builder = with types; {
    enable = mkBoolOpt false "Enable NixOS configuration builder and binary cache server";

    # Build Configuration
    flakePath =
      mkOpt str "/var/lib/nix-cache-builder/flake"
        "Local path where flake repository is cloned";

    stateDir =
      mkOpt str "/var/lib/nix-cache-builder"
        "Directory holding the clone, the frozen candidate sources and the published candidate metadata";

    flakeRepo = mkOpt str "git@github.com:sbulav/dotnix.git" "GitHub repository URL to clone";

    flakeBranch = mkOpt str "main" "Branch to track in the repository";

    flakeRef =
      mkOpt str "git+file:///var/lib/nix-cache-builder/flake"
        "Flake reference for manual commands against the clone; builds use the frozen candidate source instead";

    updateFlake = mkBoolOpt true "Resolve the newest inputs with `nix flake update` before freezing the candidate";

    hosts = mkOpt (listOf str) [
      "nz"
      "zanoza"
      "mz"
      "beez"
    ] "NixOS hosts to build, in build order: earlier entries get the budget first";

    perHostTimeout = mkOpt str "4h" "Wall-clock limit for a single host's build";

    totalBudget =
      mkOpt str "10h"
        "Wall-clock budget for the whole batch; hosts that no longer fit are recorded as skipped-budget";

    # Builds run inside nix-daemon.service's cgroup, not this unit's, so the
    # unit's CPUQuota/MemoryMax cannot reach them. These two are the only
    # levers the caller has over how much of the machine a build consumes.
    maxJobs = mkOpt int 1 "Derivations to build concurrently (nix --max-jobs)";

    buildCores =
      mkOpt int 0
        "Cores offered to each build job (nix --cores); 0 means every core on the machine";

    # Scheduling
    buildTime = mkOpt str "*-*-* 02:00:00" "When to run daily builds (systemd OnCalendar format)";

    # Storage
    cacheDir = mkOpt str "/var/cache/nix-builds" "Directory to store build result links";

    keepGenerations = mkOpt int 3 "Number of result generations to keep per host";

    keepCandidates = mkOpt int 10 "Number of candidate metadata directories to keep";

    minFreeGB =
      mkOpt int 60
        "Release old generations while the filesystem holding /nix/store has less than this many GB free";

    remoteBuilderDisableFile =
      mkOpt (nullOr str) null
        "When this file exists, force cache builds to run locally without configured remote builders";

    errorLogLines = mkOpt int 25 "Journal lines to include in a failure notification";

    # Cache Server
    cacheServer = {
      enable = mkBoolOpt true "Enable nix-serve-ng cache server";

      port = mkOpt port 5000 "Port for cache server to listen on";
    };

    # Candidate publication (metadata only, never the source tree)
    publish = {
      enable = mkBoolOpt false "Serve candidate metadata over HTTP so local machines can adopt a built lock";

      port = mkOpt port 5001 "Port for the candidate metadata server";
    };

    # Telegram Notifications
    telegram = {
      enable = mkBoolOpt false "Enable telegram notifications for build results";

      chatId = mkOpt str "681806836" "Telegram chat ID for notifications";

      proxyUrl = mkOpt str "" "Optional curl proxy URL for Telegram delivery (prefer socks5h://)";

      notifyOnSuccess = mkBoolOpt true "Send notification when all builds succeed";

      notifyOnPartialSuccess = mkBoolOpt true "Send notification when some builds fail";

      notifyOnFailure = mkBoolOpt true "Send notification when all builds fail";

      successPriority = mkOpt (enum [
        "high"
        "low"
      ]) "low" "Notification priority for complete success";

      failurePriority = mkOpt (enum [
        "high"
        "low"
      ]) "high" "Notification priority for any failures";
    };

    # Email Notifications (fallback when Telegram is unavailable)
    email = {
      enable = mkBoolOpt false "Use msmtp when Telegram delivery fails";

      recipient = mkOpt str "bulavintsev.sergey@gmail.com" "Email address to send notifications to";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base configuration
    {
      assertions = [
        {
          assertion = builtins.match durationPattern cfg.perHostTimeout != null;
          message = "custom.services.nix-cache-builder.perHostTimeout must look like 4h, 90m or 1h30m";
        }
        {
          assertion = builtins.match durationPattern cfg.totalBudget != null;
          message = "custom.services.nix-cache-builder.totalBudget must look like 10h, 600m or 10h30m";
        }
        {
          assertion = cfg.keepGenerations >= 1;
          message = "custom.services.nix-cache-builder.keepGenerations must keep at least one generation";
        }
        {
          assertion = cfg.keepCandidates >= 1;
          message = "custom.services.nix-cache-builder.keepCandidates must keep at least one candidate";
        }
        {
          assertion = cfg.maxJobs >= 1;
          message = "custom.services.nix-cache-builder.maxJobs must be at least 1";
        }
        {
          assertion = cfg.buildCores >= 0;
          message = "custom.services.nix-cache-builder.buildCores must be 0 (all cores) or positive";
        }
        {
          assertion = hasPrefix "${cfg.stateDir}/" cfg.flakePath;
          message = "custom.services.nix-cache-builder.flakePath must live inside stateDir";
        }
      ];

      # Ensure SSH is available for git operations
      # Use mkForce to override GPG module's SSH agent configuration
      programs.ssh.startAgent = mkForce true;

      # Disable GPG SSH support to avoid conflicts with standard SSH agent
      programs.gnupg.agent.enableSSHSupport = mkForce false;

      # Add GitHub to known_hosts
      programs.ssh.knownHosts = {
        "github.com" = {
          hostNames = [ "github.com" ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };
      };

      # Candidate metadata is world-readable on purpose: nginx serves it.
      systemd.tmpfiles.rules = [
        "d ${cfg.cacheDir} 0755 root root -"
        "d ${cfg.stateDir} 0755 root root -"
        "d ${cfg.flakePath} 0755 root root -"
        "d ${candidatesDir} 0755 root root -"
        "d ${sourcesDir} 0750 root root -"
      ];

      # Define SOPS secret for cache private key
      sops.secrets."nix-cache-priv-key" = {
        mode = "0400";
        owner = "root";
        group = "root";
      };

      # Define SOPS secret for telegram notifications
      sops.secrets."telegram-notifications-bot-token" = mkIf cfg.telegram.enable {
        mode = mkDefault "0400";
        owner = mkDefault "root";
        group = mkDefault "root";
      };

      # Sync service: Clone/update flake from GitHub
      systemd.services."nix-cache-builder-sync" = {
        description = "Sync NixOS flake repository from GitHub";

        environment = {
          GIT_SSH_COMMAND = "ssh -o StrictHostKeyChecking=accept-new";
        };

        script = ''
          set -euo pipefail

          FLAKE_DIR="${cfg.flakePath}"
          REPO="${cfg.flakeRepo}"
          BRANCH="${cfg.flakeBranch}"

          echo "Syncing flake from $REPO (branch: $BRANCH)..."

          if [ ! -d "$FLAKE_DIR/.git" ]; then
            echo "Cloning repository for the first time..."
            ${pkgs.git}/bin/git clone \
              --branch "$BRANCH" \
              --single-branch \
              "$REPO" \
              "$FLAKE_DIR"
          else
            echo "Updating existing repository..."
            cd "$FLAKE_DIR"

            # Fetch latest changes
            ${pkgs.git}/bin/git fetch origin "$BRANCH"

            # Hard reset to latest remote state
            ${pkgs.git}/bin/git reset --hard "origin/$BRANCH"

            # Clean any untracked files
            ${pkgs.git}/bin/git clean -fd
          fi

          echo "✓ Flake synced successfully"
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /root/.ssh";
          Environment = "PATH=${pkgs.git}/bin:${pkgs.nix}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin";

          # beez's backup and monitoring timers outrank cache work.
          CPUWeight = 20;
          IOWeight = 20;
          Nice = 10;
        };
      };

      # Build service: freeze a candidate, then build each host from it
      systemd.services."nix-cache-builder" = {
        description = "Build NixOS configurations for cache";
        after = [
          "nix-cache-builder-sync.service"
          "network-online.target"
        ];
        requires = [
          "nix-cache-builder-sync.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        onFailure = mkIf notifyEnabled [ "nix-cache-builder-failure.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Environment = "PATH=${pkgs.git}/bin:${pkgs.nix}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin";
          WorkingDirectory = cfg.flakePath;

          ExecStart = "${buildScript}/bin/nix-cache-build";
          # Runs on success, failure, SIGTERM and start-timeout alike, which is
          # the whole point: the 2026-09-10 timeout reported nothing.
          ExecStopPost = "${reportScript}/bin/nix-cache-report";

          # These bound the *client* only. Compilation happens in
          # nix-daemon.service's cgroup (measured: a build's `sleep` sat in
          # /system.slice/nix-daemon.service while the client sat in the
          # caller's slice), so no unit-level limit here can reach a builder;
          # `--max-jobs`/`--cores` above do that instead. What the client
          # actually does is evaluate four NixOS closures, which is where the
          # gigabytes go, so the memory limits are still the right ones.
          CPUWeight = 20;
          IOWeight = 20;
          Nice = 10;
          CPUQuota = "300%";
          # Begin reclaiming at 6 GiB but permit another 4 GiB before the hard
          # limit: evaluation peaked at 8 GiB, and MemoryMax kills while
          # MemoryHigh only throttles.
          MemoryHigh = "6G";
          MemoryMax = "10G";

          # The script's own budget normally ends the run; this is the backstop
          # with half an hour of slack.
          TimeoutStartSec = "${cfg.totalBudget} 30m";
          # Enough for the report step to build a message and deliver it.
          TimeoutStopSec = "10m";
        }
        // telegramEnv;
      };

      # Build timer: Schedule daily builds
      systemd.timers."nix-cache-builder" = {
        description = "Daily NixOS configuration builds with flake update";
        timerConfig = {
          OnCalendar = cfg.buildTime;
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
        wantedBy = [ "timers.target" ];
      };

      systemd.services."nix-cache-builder-failure" = mkIf notifyEnabled {
        description = "Notify about a nix-cache-builder run that reported nothing";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          TimeoutStartSec = "10min";
          ExecStart = "${failureScript}/bin/nix-cache-notify-failure";
        }
        // telegramEnv;
      };

      # Cleanup service: retention plus real store pressure
      systemd.services."nix-cache-cleanup" = {
        description = "Release old cache generations and prune candidate metadata";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Environment = "PATH=${pkgs.nix}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin";
          ExecStart = "${cleanupScript}/bin/nix-cache-cleanup";
          TimeoutStartSec = "15min";

          CPUWeight = 20;
          IOWeight = 20;
          Nice = 10;
        };
      };

      # Cleanup timer: Run hourly
      systemd.timers."nix-cache-cleanup" = {
        description = "Periodic cache cleanup";
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };
    }

    # Cache server configuration
    (mkIf cfg.cacheServer.enable {
      services.nix-serve = {
        enable = true;
        port = cfg.cacheServer.port;
        secretKeyFile = config.sops.secrets."nix-cache-priv-key".path;
        package = pkgs.nix-serve-ng;
      };

      users.groups.nix-serve = { };
      users.users.nix-serve = {
        isSystemUser = true;
        group = "nix-serve";
      };

      systemd.services.nix-serve.serviceConfig.DynamicUser = mkForce false;

      # Determinate Nix ignores extra-allowed-users; explicitly allow nix-serve user
      nix.settings.allowed-users = [ "nix-serve" ];

      # Firewall: LAN-only access
      networking.firewall.allowedTCPPorts = [ cfg.cacheServer.port ];
    })

    # Candidate publication: metadata only. The frozen source trees live in
    # ${sourcesDir}, which is outside this root and therefore unreachable.
    (mkIf cfg.publish.enable {
      services.nginx = {
        enable = true;
        virtualHosts."nix-cache-candidates" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.publish.port;
            }
          ];
          root = candidatesDir;
          locations."/".extraConfig = ''
            autoindex on;
            charset utf-8;
            default_type application/json;
          '';
        };
      };

      networking.firewall.allowedTCPPorts = [ cfg.publish.port ];
    })
  ]);
}
