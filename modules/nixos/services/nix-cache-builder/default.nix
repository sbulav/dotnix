{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.services.nix-cache-builder;

  # Explicit substituter list for build commands. `--substituters`
  # REPLACES the resolved list, so this bypasses the Determinate-injected
  # `install.determinate.systems` / `cache.flakehub.com` caches, which time
  # out (<1 B/s) and 401 from this network and otherwise poison every build.
  buildSubstituters = "https://cache.nixos.org";
in
{
  options.${namespace}.services.nix-cache-builder = with types; {
    enable = mkBoolOpt false "Enable NixOS configuration builder and binary cache server";

    # Build Configuration
    flakePath =
      mkOpt str "/var/lib/nix-cache-builder/flake"
        "Local path where flake repository is cloned";

    flakeRepo = mkOpt str "git@github.com:sbulav/dotnix.git" "GitHub repository URL to clone";

    flakeBranch = mkOpt str "main" "Branch to track in the repository";

    flakeRef =
      mkOpt str "git+file:///var/lib/nix-cache-builder/flake"
        "Flake reference for nix build commands";

    updateFlake = mkBoolOpt true "Build with a disposable nix flake update before each run";

    hosts = mkOpt (listOf str) [
      "nz"
      "zanoza"
      "mz"
      "beez"
    ] "List of NixOS hosts to build configurations for";

    # Scheduling
    buildTime = mkOpt str "*-*-* 02:00:00" "When to run daily builds (systemd OnCalendar format)";

    # Storage
    cacheDir = mkOpt str "/var/cache/nix-builds" "Directory to store build results";

    maxCacheSize = mkOpt int 200 "Maximum cache size in GB (0 = unlimited)";

    keepGenerations = mkOpt int 3 "Number of generations to keep per host";

    # Cache Server
    cacheServer = {
      enable = mkBoolOpt true "Enable nix-serve-ng cache server";

      port = mkOpt port 5000 "Port for cache server to listen on";

      priority = mkOpt int 40 "Substituter priority (lower = higher priority)";
    };

    # Telegram Notifications
    telegram = {
      enable = mkBoolOpt false "Enable telegram notifications for build results";

      chatId = mkOpt str "681806836" "Telegram chat ID for notifications";

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
      enable = mkBoolOpt false "Enable email fallback notifications for build results";

      recipient = mkOpt str "bulavintsev.sergey@gmail.com" "Email address to send notifications to";

      notifyOnSuccess = mkBoolOpt false "Send email when all builds succeed";

      notifyOnFailure = mkBoolOpt true "Send email when any builds fail";

      sendOnTelegramFailure = mkBoolOpt true "Always send email if Telegram notification fails";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base configuration
    {
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

      # Create cache directory with proper permissions
      systemd.tmpfiles.rules = [
        "d ${cfg.cacheDir} 0755 root root -"
        "d ${cfg.flakePath} 0755 root root -"
      ];

      # Define SOPS secret for cache private key
      sops.secrets."nix-cache-priv-key" = {
        mode = "0400";
        owner = "root";
        group = "root";
      };

      # Define SOPS secret for telegram notifications
      sops.secrets."telegram-notifications-bot-token" = mkIf cfg.telegram.enable {
        mode = "0400";
        owner = "root";
        group = "root";
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

          if [ ! -d "$FLAKE_DIR" ]; then
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
        };
      };

      # Build service: Build NixOS configurations
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

        script = ''
          #!/usr/bin/env bash
          set -euo pipefail

          FLAKE_DIR="${cfg.flakePath}"
          FLAKE="${cfg.flakeRef}"
          CACHE_DIR="${cfg.cacheDir}"

          mkdir -p "$CACHE_DIR"

          cd "$FLAKE_DIR"

          # Statistics tracking for telegram notifications
          TOTAL_START=$(date +%s)
          SUCCESS_COUNT=0
          FAILED_COUNT=0
          BUILD_RESULTS=""
          PREPARATION_FAILED=0
          INPUT_UPDATE_STATUS="disabled"
          SOURCE_REV=$(${pkgs.git}/bin/git rev-parse HEAD)
          SOURCE_SHORT=$(${pkgs.git}/bin/git rev-parse --short=12 HEAD)

          # The candidate lock is intentionally disposable. The sync service resets
          # the checkout to the configured remote branch before every run. This
          # never needs a commit, Git identity, branch, or push.
          ${optionalString cfg.updateFlake ''
            echo "Updating flake inputs..."
            if ${pkgs.nix}/bin/nix flake update; then
              INPUT_UPDATE_STATUS="updated"
              echo "✓ Flake inputs updated successfully"
            else
              ${pkgs.git}/bin/git restore --source=HEAD -- flake.lock
              INPUT_UPDATE_STATUS="failed; using source lock"
              PREPARATION_FAILED=1
              echo "⚠ Failed to update flake inputs; building the committed source lock" >&2
            fi
          ''}

          LOCK_FINGERPRINT=$(${pkgs.coreutils}/bin/sha256sum flake.lock | ${pkgs.coreutils}/bin/cut -d' ' -f1)
          METADATA_JSON=$(${pkgs.coreutils}/bin/mktemp)
          trap '${pkgs.coreutils}/bin/rm -f "$METADATA_JSON"' EXIT

          if ${pkgs.nix}/bin/nix flake metadata --json "$FLAKE" > "$METADATA_JSON"; then
            FLAKE_FINGERPRINT=$(${pkgs.jq}/bin/jq -r '.fingerprint // "unknown"' "$METADATA_JSON")
            RESOLVED_INPUTS=$(${pkgs.jq}/bin/jq -r '
              .locks.nodes as $nodes
              | .locks.nodes.root.inputs
              | to_entries[]
              | .key as $name
              | (.value | if type == "array" then .[0] else . end) as $node
              | $nodes[$node].locked as $locked
              | "\($name)=\($locked.rev // $locked.ref // ($locked.lastModified // "unversioned" | tostring))"
            ' "$METADATA_JSON" | ${pkgs.coreutils}/bin/sort)
          else
            FLAKE_FINGERPRINT="unavailable"
            RESOLVED_INPUTS="unavailable"
            PREPARATION_FAILED=1
            echo "⚠ Failed to collect flake metadata; builds will still be attempted" >&2
          fi

          echo "=== Flake Information ==="
          echo "Source revision: $SOURCE_REV"
          echo "Input update: $INPUT_UPDATE_STATUS"
          echo "Candidate lock SHA-256: $LOCK_FINGERPRINT"
          echo "Flake fingerprint: $FLAKE_FINGERPRINT"
          echo "Resolved direct inputs:"
          echo "$RESOLVED_INPUTS"
          echo "========================"

          # Build each host
          ${concatMapStringsSep "\n" (host: ''
                        echo ""
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        echo "Building configuration for ${host}..."
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

                        RESULT_LINK="$CACHE_DIR/${host}-result"
                        CANDIDATE_LINK="$CACHE_DIR/.${host}-candidate-result"
                        ${pkgs.coreutils}/bin/rm -f "$CANDIDATE_LINK"

                        BUILD_START=$(date +%s)
                        BUILD_OK=false
                        if ${pkgs.nix}/bin/nix build \
                          --out-link "$CANDIDATE_LINK" \
                          "$FLAKE#nixosConfigurations.${host}.config.system.build.toplevel" \
                          --substituters "${buildSubstituters}" \
                          --print-build-logs \
                          --keep-going; then
                          echo "Signing store paths for ${host}..."
                          if ${pkgs.nix}/bin/nix store sign \
                            --recursive \
                            --key-file ${config.sops.secrets."nix-cache-priv-key".path} \
                            "$CANDIDATE_LINK"; then
                            if ${pkgs.coreutils}/bin/mv -Tf "$CANDIDATE_LINK" "$RESULT_LINK"; then
                              BUILD_OK=true
                              echo "✓ Signed and published ${host}"
                            else
                              echo "✗ Failed to publish ${host}; previous result preserved" >&2
                            fi
                          else
                            echo "✗ Failed to sign ${host}; previous result preserved" >&2
                          fi
                        else
                          echo "✗ Failed to build ${host}; previous result preserved" >&2
                        fi

                        BUILD_END=$(date +%s)
                        BUILD_TIME=$((BUILD_END - BUILD_START))
                        if [ "$BUILD_OK" = true ]; then
                          echo "✓ Successfully built ${host} in ''${BUILD_TIME}s"
                          SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                          BUILD_RESULTS="''${BUILD_RESULTS}✅ ${host}: ''${BUILD_TIME}s
            "
                        else
                          ${pkgs.coreutils}/bin/rm -f "$CANDIDATE_LINK"
                          echo "✗ ${host} attempt failed after ''${BUILD_TIME}s" >&2
                          FAILED_COUNT=$((FAILED_COUNT + 1))
                          BUILD_RESULTS="''${BUILD_RESULTS}❌ ${host}: ''${BUILD_TIME}s ✗
            "
                        fi
          '') cfg.hosts}

          TOTAL_END=$(date +%s)
          TOTAL_TIME=$((TOTAL_END - TOTAL_START))

          if [ "$SUCCESS_COUNT" -eq 0 ]; then
            STATUS_TEXT="FAILED"
          elif [ "$FAILED_COUNT" -gt 0 ] || [ "$PREPARATION_FAILED" -gt 0 ]; then
            STATUS_TEXT="PARTIAL"
          else
            STATUS_TEXT="SUCCESS"
          fi

          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "Build summary:"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "Status: $STATUS_TEXT"
          echo "Source revision: $SOURCE_REV"
          echo "Input update: $INPUT_UPDATE_STATUS"
          echo "Candidate lock SHA-256: $LOCK_FINGERPRINT"
          echo "Flake fingerprint: $FLAKE_FINGERPRINT"
          printf '%s' "$BUILD_RESULTS"
          ls -lh "$CACHE_DIR/"*-result 2>/dev/null || echo "No builds found"

          # Cleanup old generations
          echo ""
          echo "Cleaning up old generations..."
           REMOVED=$(${pkgs.findutils}/bin/find "$CACHE_DIR" \
             -name '*-result-*' \
             -mtime +${toString (cfg.keepGenerations * 7)} \
             -delete -print | ${pkgs.coreutils}/bin/wc -l)
          echo "✓ Removed $REMOVED old generation symlinks"

          echo ""
           echo "=== Cache Statistics ==="
           echo "Current cache size: $(${pkgs.coreutils}/bin/du -sh $CACHE_DIR | ${pkgs.coreutils}/bin/cut -f1)"
           echo "Available disk space: $(${pkgs.coreutils}/bin/df -h $CACHE_DIR | ${pkgs.coreutils}/bin/tail -1 | ${pkgs.gawk}/bin/awk '{print $4}')"
           echo "======================="

          ${optionalString (cfg.telegram.enable || cfg.email.enable) ''
            # Prepare notification message
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Preparing notifications..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            DISK_FREE=$(${pkgs.coreutils}/bin/df -h "$CACHE_DIR" | ${pkgs.coreutils}/bin/tail -1 | ${pkgs.gawk}/bin/awk '{print $4}')

            # Format total time (convert seconds to human readable)
            TOTAL_MINUTES=$((TOTAL_TIME / 60))
            TOTAL_SECONDS=$((TOTAL_TIME % 60))
            if [ $TOTAL_MINUTES -gt 0 ]; then
              TIME_HUMAN="''${TOTAL_MINUTES}m ''${TOTAL_SECONDS}s"
            else
              TIME_HUMAN="''${TOTAL_SECONDS}s"
            fi

            # Build notification message
            message=$(printf 'Cache Build: %s\nSource: %s\nInput update: %s\nLock: %.12s\nFlake: %.12s\n==========\n%s\n==========\n⏱️ %s total\n💿 Free: %s\nDirect inputs:\n%s' \
              "$STATUS_TEXT" \
              "$SOURCE_SHORT" \
              "$INPUT_UPDATE_STATUS" \
              "$LOCK_FINGERPRINT" \
              "$FLAKE_FINGERPRINT" \
              "$BUILD_RESULTS" \
              "$TIME_HUMAN" \
              "$DISK_FREE" \
              "$RESOLVED_INPUTS")

            TELEGRAM_SENT="false"
          ''}

          ${optionalString cfg.telegram.enable ''
            # Determine Telegram notification priority
            if [ "$STATUS_TEXT" = "SUCCESS" ]; then
              TG_SHOULD_NOTIFY="${if cfg.telegram.notifyOnSuccess then "true" else "false"}"
              PRIORITY="${cfg.telegram.successPriority}"
            elif [ "$STATUS_TEXT" = "FAILED" ]; then
              TG_SHOULD_NOTIFY="${if cfg.telegram.notifyOnFailure then "true" else "false"}"
              PRIORITY="${cfg.telegram.failurePriority}"
            else
              TG_SHOULD_NOTIFY="${if cfg.telegram.notifyOnPartialSuccess then "true" else "false"}"
              PRIORITY="${cfg.telegram.failurePriority}"
            fi

            if [ "$TG_SHOULD_NOTIFY" = "true" ]; then
              echo "📱 Sending Telegram notification (priority: $PRIORITY)..."

              disable_notification=$([ "$PRIORITY" = "low" ] && echo "true" || echo "false")

              data=$(${pkgs.jq}/bin/jq -n \
                --arg chat_id "${cfg.telegram.chatId}" \
                --arg text "$message" \
                --argjson disable_notification "$disable_notification" \
                '{chat_id: $chat_id, text: $text, disable_notification: $disable_notification}')

              response=$(${pkgs.curl}/bin/curl -s --connect-timeout 10 --max-time 30 -X POST \
                -H 'Content-Type: application/json' \
                -d "$data" \
                "https://api.telegram.org/bot''${TELEGRAM_TOKEN}/sendMessage") || {
                echo "⚠️ Failed to send Telegram notification (network error)" >&2
              }

              if echo "$response" | ${pkgs.jq}/bin/jq -e '.ok' >/dev/null 2>&1; then
                echo "✓ Telegram notification sent successfully"
                TELEGRAM_SENT="true"
              else
                echo "⚠️ Telegram notification failed" >&2
                echo "Response: $response" >&2
              fi
            else
              echo "Skipping Telegram notification (disabled for $STATUS_TEXT)"
              TELEGRAM_SENT="skipped"
            fi
          ''}

          ${optionalString cfg.email.enable ''
            # Determine if email should be sent
            EMAIL_SHOULD_SEND="false"
            EMAIL_NOTIFY_SUCCESS="${if cfg.email.notifyOnSuccess then "true" else "false"}"
            EMAIL_NOTIFY_FAILURE="${if cfg.email.notifyOnFailure then "true" else "false"}"

            # Send email if Telegram failed and sendOnTelegramFailure is enabled
            ${optionalString cfg.email.sendOnTelegramFailure ''
              if [ "$TELEGRAM_SENT" = "false" ]; then
                EMAIL_SHOULD_SEND="true"
                echo "📧 Telegram failed, falling back to email..."
              fi
            ''}

            # Send email based on build status
            if [ "$STATUS_TEXT" = "SUCCESS" ] && [ "$EMAIL_NOTIFY_SUCCESS" = "true" ]; then
              EMAIL_SHOULD_SEND="true"
            elif [ "$STATUS_TEXT" != "SUCCESS" ] && [ "$EMAIL_NOTIFY_FAILURE" = "true" ]; then
              EMAIL_SHOULD_SEND="true"
            fi

            if [ "$EMAIL_SHOULD_SEND" = "true" ]; then
              echo "📧 Sending email notification to ${cfg.email.recipient}..."

              printf 'Subject: [nix-cache-builder] %s - %s\nFrom: ZANOZA-notifications <zppfan@gmail.com>\nTo: ${cfg.email.recipient}\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' \
                "$STATUS_TEXT" \
                "$(date '+%Y-%m-%d %H:%M')" \
                "$message" | ${pkgs.msmtp}/bin/msmtp -a gmail "${cfg.email.recipient}" && {
                echo "✓ Email notification sent successfully"
              } || {
                echo "⚠️ Failed to send email notification" >&2
              }
            else
              echo "Skipping email notification"
            fi
          ''}

          # Report an all-host failure to systemd. The service is not restarted
          # automatically, so each scheduled run attempts every host exactly once.
          if [ "$SUCCESS_COUNT" -eq 0 ]; then
            exit 1
          fi
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Environment = "PATH=${pkgs.git}/bin:${pkgs.nix}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin";
          WorkingDirectory = cfg.flakePath;

          # Limit resources. 250% = 2.5 of 4 cores: leaves headroom and caps
          # heat while still letting the rare from-source build finish in time.
          CPUQuota = "250%";
          # Begin reclaiming at 8 GiB but permit another 2 GiB before a hard
          # limit. This fits beez's 12 GiB RAM without forcing normal builds to
          # swap as aggressively as the previous 8 GiB hard cap.
          MemoryHigh = "8G";
          MemoryMax = "10G";

          # Increase timeout for long builds
          TimeoutStartSec = "6h";

        }
        // (optionalAttrs cfg.telegram.enable {
          EnvironmentFile = config.sops.secrets."telegram-notifications-bot-token".path;
        });
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

      # Cleanup service: Monitor cache size
      systemd.services."nix-cache-cleanup" = mkIf (cfg.maxCacheSize > 0) {
        description = "Clean up nix cache if size exceeds limit";
        script = ''
          CURRENT_SIZE=$(${pkgs.coreutils}/bin/du -sb ${cfg.cacheDir} | cut -f1)
          MAX_SIZE=$((${toString cfg.maxCacheSize} * 1024 * 1024 * 1024))

          if [ "$CURRENT_SIZE" -gt "$MAX_SIZE" ]; then
            echo "Cache size $CURRENT_SIZE exceeds limit $MAX_SIZE"
            # Remove oldest builds first
            ${pkgs.findutils}/bin/find ${cfg.cacheDir} -name '*-result*' -type l -printf '%T+ %p\n' | \
              sort | head -n 5 | cut -d' ' -f2- | xargs rm -f
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      # Cleanup timer: Run hourly
      systemd.timers."nix-cache-cleanup" = mkIf (cfg.maxCacheSize > 0) {
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
      networking.firewall = {
        allowedTCPPorts = [ cfg.cacheServer.port ];

        # # Restrict to LAN only (192.168.0.0/16)
        # extraCommands = ''
        #   # Allow only local networks to access cache server
        #   iptables -I nixos-fw -p tcp --dport ${toString cfg.cacheServer.port} \
        #     -s 192.168.0.0/16 -j nixos-fw-accept
        #   iptables -I nixos-fw -p tcp --dport ${toString cfg.cacheServer.port} -j nixos-fw-refuse
        # '';

        # extraStopCommands = ''
        #   iptables -D nixos-fw -p tcp --dport ${toString cfg.cacheServer.port} \
        #     -s 192.168.0.0/16 -j nixos-fw-accept 2>/dev/null || true
        #   iptables -D nixos-fw -p tcp --dport ${toString cfg.cacheServer.port} \
        #     -j nixos-fw-refuse 2>/dev/null || true
        # '';
      };
    })
  ]);
}
