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

    updateFlake = mkBoolOpt true "Run nix flake update before each build";

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
        };
      };

      # Build service: Build NixOS configurations
      systemd.services."nix-cache-builder" = {
        description = "Build NixOS configurations for cache";
        wants = [ "nix-cache-builder-sync.service" ];
        after = [
          "nix-cache-builder-sync.service"
          "network-online.target"
        ];
        requires = [ "network-online.target" ];

        script = ''
          #!/usr/bin/env bash
          set -euo pipefail

          FLAKE_DIR="${cfg.flakePath}"
          FLAKE="${cfg.flakeRef}"
          CACHE_DIR="${cfg.cacheDir}"

          mkdir -p "$CACHE_DIR"

          cd "$FLAKE_DIR"

          # Update flake inputs before building
          ${optionalString cfg.updateFlake ''
            echo "Updating flake inputs..."
            if ${pkgs.nix}/bin/nix flake update --commit-lock-file; then
              echo "✓ Flake inputs updated successfully"
            else
              echo "⚠ Warning: Failed to update flake inputs, continuing with existing lock file"
            fi
          ''}

          # Display flake info for logging
          echo "=== Flake Information ==="
          ${pkgs.nix}/bin/nix flake metadata "$FLAKE"
          echo "========================"

          # Build each host
          ${concatMapStringsSep "\n" (host: ''
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Building configuration for ${host}..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            BUILD_START=$(date +%s)

            if ${pkgs.nix}/bin/nix build \
              --out-link "$CACHE_DIR/${host}-result" \
              "$FLAKE#nixosConfigurations.${host}.config.system.build.toplevel" \
              --print-build-logs \
              --keep-going; then
              
              BUILD_END=$(date +%s)
              BUILD_TIME=$((BUILD_END - BUILD_START))
              
              echo "✓ Successfully built ${host} in ''${BUILD_TIME}s"
              
              # Sign the store paths
              echo "Signing store paths for ${host}..."
              ${pkgs.nix}/bin/nix store sign \
                --recursive \
                --key-file ${config.sops.secrets."nix-cache-priv-key".path} \
                "$CACHE_DIR/${host}-result"
              
              echo "✓ Signed store paths for ${host}"
              
            else
              BUILD_END=$(date +%s)
              BUILD_TIME=$((BUILD_END - BUILD_START))
              
              echo "✗ Failed to build ${host} after ''${BUILD_TIME}s" >&2
              # Continue with next host instead of failing entirely
            fi
          '') cfg.hosts}

          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "Build summary:"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          ls -lh "$CACHE_DIR/"*-result 2>/dev/null || echo "No builds found"

          # Cleanup old generations
          echo ""
          echo "Cleaning up old generations..."
          REMOVED=$(${pkgs.findutils}/bin/find "$CACHE_DIR" \
            -name '*-result-*' \
            -mtime +${toString (cfg.keepGenerations * 7)} \
            -delete -print | wc -l)
          echo "✓ Removed $REMOVED old generation symlinks"

          echo ""
          echo "=== Cache Statistics ==="
          echo "Current cache size: $(${pkgs.coreutils}/bin/du -sh $CACHE_DIR | cut -f1)"
          echo "Available disk space: $(${pkgs.coreutils}/bin/df -h $CACHE_DIR | tail -1 | awk '{print $4}')"
          echo "======================="
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
          WorkingDirectory = cfg.flakePath;

          # Limit resources
          CPUQuota = "80%";
          MemoryMax = "8G";

          # Increase timeout for long builds
          TimeoutStartSec = "6h";

          # Restart on failure (transient network issues, etc.)
          Restart = "on-failure";
          RestartSec = "30m";
        };
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
