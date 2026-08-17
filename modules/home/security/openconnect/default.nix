{
  namespace,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.security.openconnect;
  isLinux = pkgs.stdenv.isLinux;

  sudoBin = if isLinux then "/run/wrappers/bin/sudo" else "/usr/bin/sudo";
  psBin = if isLinux then "${pkgs.procps}/bin/ps" else "/bin/ps";
  routeBin = if isLinux then "${pkgs.iproute2}/bin/ip" else "/sbin/route";
  rootGroup = if isLinux then "root" else "wheel";
  stateRoot = if isLinux then "/run" else "/var/run";

  splitDnsServers = escapeShellArgs cfg.splitDns.servers;
  splitDnsDomains = escapeShellArgs cfg.splitDns.domains;

  # Ownership marker written into every /etc/resolver file myvpn creates, so
  # cleanup can recognise its own entries without depending on state under
  # /var/run (which macOS clears on boot) and can refuse to clobber resolver
  # files owned by someone else (e.g. custom.networking.split-dns).
  resolverMarker = "# managed by myvpn (openconnect split DNS)";

  linuxNetworkFunctions = ''
    tunnel_ready() {
      ${pkgs.iproute2}/bin/ip link show "$INTERFACE" >/dev/null 2>&1
    }

    route_up() {
      "$SUDO_BIN" "$ROUTE_BIN" route del "$LAN_CIDR" >/dev/null 2>&1 || true
      "$SUDO_BIN" "$ROUTE_BIN" route replace "$VPN_HOST_ROUTE" via "$LAN_GATEWAY"
    }

    route_down() {
      "$SUDO_BIN" "$ROUTE_BIN" route del "$VPN_HOST_ROUTE" via "$LAN_GATEWAY" >/dev/null 2>&1 || true
    }

    dns_up() {
      if ! "$SUDO_BIN" ${pkgs.systemd}/bin/systemctl -q is-active systemd-resolved.service; then
        return 0
      fi

      "$SUDO_BIN" ${pkgs.systemd}/bin/resolvectl dns "$INTERFACE" "''${SPLIT_DNS_SERVERS[@]}" || return 1

      local domains=()
      local domain
      for domain in "''${SPLIT_DNS_DOMAINS[@]}"; do
        domains+=("~$domain")
      done
      "$SUDO_BIN" ${pkgs.systemd}/bin/resolvectl domain "$INTERFACE" "''${domains[@]}" || return 1
      "$SUDO_BIN" ${pkgs.systemd}/bin/resolvectl default-route "$INTERFACE" no || return 1
      "$SUDO_BIN" ${pkgs.systemd}/bin/resolvectl flush-caches || return 1
    }

    dns_down() {
      if "$SUDO_BIN" ${pkgs.systemd}/bin/systemctl -q is-active systemd-resolved.service; then
        "$SUDO_BIN" ${pkgs.systemd}/bin/resolvectl revert "$INTERFACE" >/dev/null 2>&1 || true
        "$SUDO_BIN" ${pkgs.systemd}/bin/resolvectl flush-caches >/dev/null 2>&1 || true
      fi
    }

    # resolvectl state is per-interface and does not survive a reboot, so there
    # is never stale split DNS to report on Linux.
    dns_is_configured() {
      return 1
    }
  '';

  darwinNetworkFunctions = ''
    tunnel_ready() {
      return 0
    }

    route_up() {
      "$SUDO_BIN" "$ROUTE_BIN" delete -net "$LAN_CIDR" >/dev/null 2>&1 || true
      "$SUDO_BIN" "$ROUTE_BIN" delete -net "$VPN_HOST_ROUTE" "$LAN_GATEWAY" >/dev/null 2>&1 || true
      "$SUDO_BIN" "$ROUTE_BIN" add -net "$VPN_HOST_ROUTE" "$LAN_GATEWAY"
    }

    route_down() {
      "$SUDO_BIN" "$ROUTE_BIN" delete -net "$VPN_HOST_ROUTE" "$LAN_GATEWAY" >/dev/null 2>&1 || true
    }

    resolver_is_ours() {
      ${pkgs.gnugrep}/bin/grep -qxF "$RESOLVER_MARKER" "''${1}" 2>/dev/null
    }

    flush_dns() {
      "$SUDO_BIN" /usr/bin/dscacheutil -flushcache || return 1
      "$SUDO_BIN" /usr/bin/killall -HUP mDNSResponder || return 1
    }

    dns_up() {
      "$SUDO_BIN" ${pkgs.coreutils}/bin/mkdir -p /etc/resolver || return 1

      local domain
      local server
      local resolver_file
      for domain in "''${SPLIT_DNS_DOMAINS[@]}"; do
        resolver_file="/etc/resolver/$domain"

        if [[ -e "$resolver_file" ]] && ! resolver_is_ours "$resolver_file"; then
          echo "ERROR: $resolver_file is not managed by myvpn; refusing to overwrite it" >&2
          return 1
        fi

        {
          printf '%s\n' "$RESOLVER_MARKER"
          for server in "''${SPLIT_DNS_SERVERS[@]}"; do
            printf 'nameserver %s\n' "$server"
          done
        } | "$SUDO_BIN" ${pkgs.coreutils}/bin/tee "$resolver_file" >/dev/null || return 1
      done

      flush_dns
    }

    # Removes our own resolver entries wherever they are found. This must not
    # depend on $STATE_DIR: /etc/resolver survives a reboot but /var/run does
    # not, so a state-dir-gated cleanup leaked corp-only nameservers into every
    # later boot and made the split DNS domains resolve nowhere.
    dns_down() {
      local failed=0
      local domain
      local resolver_file
      for domain in "''${SPLIT_DNS_DOMAINS[@]}"; do
        resolver_file="/etc/resolver/$domain"
        [[ -e "$resolver_file" ]] || continue

        if resolver_is_ours "$resolver_file"; then
          "$SUDO_BIN" ${pkgs.coreutils}/bin/rm -f "$resolver_file" || failed=1
        else
          echo "WARNING: $resolver_file is not managed by myvpn; leaving it in place" >&2
        fi
      done

      flush_dns >/dev/null 2>&1 || true
      return "$failed"
    }

    dns_is_configured() {
      local domain
      for domain in "''${SPLIT_DNS_DOMAINS[@]}"; do
        if resolver_is_ours "/etc/resolver/$domain"; then
          return 0
        fi
      done
      return 1
    }
  '';

  networkFunctions = if isLinux then linuxNetworkFunctions else darwinNetworkFunctions;

  vpnScript = pkgs.writeShellApplication {
    name = "myvpn";
    runtimeInputs = [
      cfg.package
      pkgs.coreutils
    ]
    ++ optionals isLinux [
      pkgs.iproute2
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      OPENCONNECT_BIN="${lib.getExe cfg.package}"
      SUDO_BIN="${sudoBin}"
      PS_BIN="${psBin}"
      ROUTE_BIN="${routeBin}"
      ${optionalString isLinux "INTERFACE=${escapeShellArg cfg.interface}"}
      CREDENTIALS_FILE=${escapeShellArg cfg.credentialsFile}
      LAN_CIDR=${escapeShellArg cfg.routes.lanCidr}
      VPN_HOST_ROUTE=${escapeShellArg cfg.routes.vpnHostRoute}
      LAN_GATEWAY=${escapeShellArg cfg.routes.lanGateway}
      STATE_DIR="${stateRoot}/myvpn-$UID"
      PID_FILE="$STATE_DIR/openconnect.pid"
      SPLIT_DNS_SERVERS=( ${splitDnsServers} )
      SPLIT_DNS_DOMAINS=( ${splitDnsDomains} )
      ${optionalString (!isLinux) "RESOLVER_MARKER=${escapeShellArg resolverMarker}"}

      ${networkFunctions}

      usage() {
        echo "Usage: myvpn <up|down|status>" >&2
      }

      ensure_state_dir() {
        "$SUDO_BIN" ${pkgs.coreutils}/bin/install -d -o root -g ${rootGroup} -m 0755 "$STATE_DIR"
      }

      remove_state_dir() {
        "$SUDO_BIN" ${pkgs.coreutils}/bin/rm -rf "$STATE_DIR"
      }

      load_credentials() {
        if [[ -n "''${OPENCONNECT_USER:-}" && -n "''${OPENCONNECT_PW:-}" && -n "''${OPENCONNECT_SERVER:-}" ]]; then
          return 0
        fi

        if [[ -r "$CREDENTIALS_FILE" ]]; then
          set +u
          # shellcheck source=/dev/null
          source "$CREDENTIALS_FILE"
          set -u
        fi
      }

      require_credentials() {
        load_credentials

        local missing=0
        if [[ -z "''${OPENCONNECT_USER:-}" ]]; then
          echo "ERROR: OPENCONNECT_USER is not set in the environment or $CREDENTIALS_FILE" >&2
          missing=1
        fi
        if [[ -z "''${OPENCONNECT_PW:-}" ]]; then
          echo "ERROR: OPENCONNECT_PW is not set in the environment or $CREDENTIALS_FILE" >&2
          missing=1
        fi
        if [[ -z "''${OPENCONNECT_SERVER:-}" ]]; then
          echo "ERROR: OPENCONNECT_SERVER is not set in the environment or $CREDENTIALS_FILE" >&2
          missing=1
        fi
        [[ "$missing" -eq 0 ]]
      }

      read_pid() {
        local pid
        pid="$(${pkgs.coreutils}/bin/cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
          printf '%s\n' "$pid"
        fi
      }

      pid_is_ours() {
        local pid="''${1:-}"
        local command
        [[ "$pid" =~ ^[0-9]+$ ]] || return 1
        command="$("$PS_BIN" -p "$pid" -o command= 2>/dev/null)" || return 1
        [[ "$command" == *"$OPENCONNECT_BIN"* ]]
      }

      wait_for_connection() {
        local pid
        for _ in {1..40}; do
          if [[ -f "$PID_FILE" ]]; then
            "$SUDO_BIN" ${pkgs.coreutils}/bin/chmod 0644 "$PID_FILE" || true
          fi
          pid="$(read_pid)"
          if pid_is_ours "$pid" && tunnel_ready; then
            return 0
          fi
          sleep 0.25
        done
        return 1
      }

      stop_process() {
        local pid="''${1:-}"
        pid_is_ours "$pid" || return 0

        "$SUDO_BIN" ${pkgs.coreutils}/bin/kill -INT "$pid"
        for _ in {1..40}; do
          pid_is_ours "$pid" || return 0
          sleep 0.25
        done
        return 1
      }

      network_up() {
        route_up || return 1
        ${if cfg.splitDns.enable then "dns_up || return 1" else ":"}
      }

      network_down() {
        local failed=0
        ${if cfg.splitDns.enable then "dns_down || failed=1" else ":"}
        route_down || failed=1
        return "$failed"
      }

      do_up() {
        local pid
        require_credentials

        pid="$(read_pid)"
        if pid_is_ours "$pid"; then
          echo "myvpn is already up (pid $pid)"
          return 0
        fi

        ensure_state_dir
        "$SUDO_BIN" ${pkgs.coreutils}/bin/rm -f "$PID_FILE"

        local openconnect_args=(
          --background
          --pid-file "$PID_FILE"
          --passwd-on-stdin
          -u "$OPENCONNECT_USER"
        )
        ${optionalString cfg.disableDtls "openconnect_args+=(--no-dtls)"}
        ${optionalString isLinux ''openconnect_args+=(--interface "$INTERFACE")''}

        if ! printf '%s\n' "$OPENCONNECT_PW" | "$SUDO_BIN" "$OPENCONNECT_BIN" "''${openconnect_args[@]}" "$OPENCONNECT_SERVER"; then
          unset OPENCONNECT_PW
          remove_state_dir || true
          echo "ERROR: openconnect failed to start" >&2
          return 1
        fi
        unset OPENCONNECT_PW

        if ! wait_for_connection; then
          pid="$(read_pid)"
          stop_process "$pid" || true
          remove_state_dir || true
          echo "ERROR: openconnect did not create a live tunnel" >&2
          return 1
        fi

        pid="$(read_pid)"
        if ! network_up; then
          network_down || true
          stop_process "$pid" || true
          remove_state_dir || true
          echo "ERROR: failed to configure VPN routes or DNS" >&2
          return 1
        fi

        echo "myvpn is up (pid $pid)"
      }

      do_down() {
        local pid
        local failed=0
        pid="$(read_pid)"

        # Always reconcile routes and DNS, even with no state dir: openconnect
        # dying on suspend or a reboot wiping /var/run must still be cleanable.
        network_down || failed=1
        stop_process "$pid" || failed=1

        if [[ -d "$STATE_DIR" ]]; then
          remove_state_dir || failed=1
        fi

        if [[ "$failed" -ne 0 ]]; then
          echo "ERROR: myvpn cleanup was incomplete" >&2
          return 1
        fi

        echo "myvpn is down"
      }

      do_status() {
        local pid
        pid="$(read_pid)"
        if pid_is_ours "$pid"; then
          echo "myvpn is up (pid $pid)"
          return 0
        fi

        echo "myvpn is down"
        ${
          if cfg.splitDns.enable then
            ''
              if dns_is_configured; then
                echo "WARNING: stale myvpn split DNS is still active in /etc/resolver;" >&2
                echo "         those domains resolve only through the VPN. Run 'myvpn down' to clear it." >&2
              fi''
          else
            ":"
        }
        return 1
      }

      case "''${1:-}" in
        up)
          do_up
          ;;
        down)
          do_down
          ;;
        status)
          do_status
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.${namespace}.security.openconnect = with types; {
    enable = mkBoolOpt false "Whether to install OpenConnect and the myvpn wrapper.";
    package = mkOpt package pkgs.openconnect "The OpenConnect package to use.";
    interface = mkOpt str "tun0" "The Linux tunnel interface used for split DNS.";
    credentialsFile = mkOpt str "${config.home.homeDirectory}/.ssh/sops-env-credentials" ''
      Shell-sourceable credentials file used when OPENCONNECT_USER,
      OPENCONNECT_PW, or OPENCONNECT_SERVER are absent from the environment.
    '';
    disableDtls = mkBoolOpt true "Whether to disable DTLS for the OpenConnect session.";

    routes = {
      lanCidr = mkOpt str "192.168.0.0/16" "The VPN-pushed LAN route to remove after connecting.";
      vpnHostRoute = mkOpt str "10.8.0.1/32" "The host route to keep outside the VPN.";
      lanGateway = mkOpt str (
        if isLinux then "192.168.90.1" else "192.168.89.1"
      ) "The LAN gateway for the host route kept outside the VPN.";
    };

    splitDns = {
      enable = mkBoolOpt true "Whether to configure split DNS while the VPN is connected.";
      servers = mkOpt (listOf str) [
        "94.124.205.83"
        "94.124.204.83"
      ] "The nameservers used for VPN-only domains.";
      domains = mkOpt (listOf str) [
        "pyn.ru"
        "hh.ru"
        "hhdev.ru"
      ] "The domains resolved through the VPN nameservers.";
    };

    scriptPackage = mkOption {
      type = nullOr package;
      default = vpnScript;
      readOnly = true;
      description = "The generated myvpn package for integration with other Home Manager modules.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
      vpnScript
    ];
  };
}
