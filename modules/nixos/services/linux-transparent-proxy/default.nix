{
  config,
  lib,
  pkgs,
  namespace,
  ...
}: let
  inherit (lib) types mkIf mkOption mkEnableOption concatStringsSep optionalString;
  inherit (lib.${namespace}) mkBoolOpt mkOpt;

  cfg = config.${namespace}.services.linuxTransparentProxy;

  iptables = "${pkgs.iptables}/bin/iptables";
  ip6tables = "${pkgs.iptables}/bin/ip6tables";
  ip = "${pkgs.iproute2}/bin/ip";
  ipsetBin = "${pkgs.ipset}/bin/ipset";

  # user chains
  natChain = "TPROXY_REDSOCKS";
  mangleChain = "TPROXY_REDSOCKS_MANGLE";

  # defaults
  defaultExcludeCidrs = [
    # RFC1918
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    # link-local & loopback & multicast/broadcast typical skip sets
    "169.254.0.0/16"
    "127.0.0.0/8"
    "224.0.0.0/4"
    "255.255.255.255/32"
  ];

  redsocksConf = mode:
    pkgs.writeText "redsocks.conf" ''
      base {
        log_debug = off;
        log_info = on;
        log = stderr;
        daemon = off;
        redirector = ${
        if mode == "tproxy"
        then "tproxy"
        else "iptables"
      };
      }
      redsocks {
        local_ip = 0.0.0.0;
        local_port = ${toString cfg.listenPort};
        ip = "${cfg.v2rayAHost}";
        port = ${toString cfg.v2rayAPort};
        type = socks5;
      }
    '';

  # shell fragments shared across services
  mkIpSetSetup = ''
    # Create set if enabled and entries are provided
    ${optionalString (cfg.ipset.enable) ''
      ${ipsetBin} list ${cfg.ipset.name} >/dev/null 2>&1 || ${ipsetBin} create ${cfg.ipset.name} hash:ip family inet -exist
      ${concatStringsSep "\n" (map (cidr: ''
          ${ipsetBin} add ${cfg.ipset.name} ${cidr} -exist
        '')
        cfg.ipset.entries)}
    ''}
  '';

  mkNatAttachJump = iface: ''
    # Ensure custom chain exists and is attached idempotently
    ${iptables} -t nat -N ${natChain} 2>/dev/null || true
    ${iptables} -t nat -C PREROUTING -i ${iface} -j ${natChain} 2>/dev/null || ${iptables} -t nat -A PREROUTING -i ${iface} -j ${natChain}
    # Clear our chain before adding rules (idempotent re-apply)
    ${iptables} -t nat -F ${natChain}
  '';

  mkNatRules = ''
    # Skip excluded CIDRs
    ${concatStringsSep "\n" (map (cidr: ''
      ${iptables} -t nat -A ${natChain} -d ${cidr} -j RETURN
    '') (cfg.excludeCidrs ++ []))}

    # Never proxy traffic going TO the proxy host itself
    ${iptables} -t nat -A ${natChain} -d ${cfg.v2rayAHost} -j RETURN

    # Optional ipset scoping ("desired sites")
    ${optionalString (cfg.ipset.enable) ''
      # If ipset is enabled, we only redirect when dst matches the set
      ${
        if cfg.tcpPorts == []
        then ''
          ${iptables} -t nat -A ${natChain} -p tcp -m set --match-set ${cfg.ipset.name} dst -m conntrack --ctstate NEW -j REDIRECT --to-ports ${toString cfg.listenPort}
        ''
        else
          concatStringsSep "\n" (map (p: ''
              ${iptables} -t nat -A ${natChain} -p tcp --dport ${toString p} -m set --match-set ${cfg.ipset.name} dst -j REDIRECT --to-ports ${toString cfg.listenPort}
            '')
            cfg.tcpPorts)
      }
    ''}

    # Otherwise, redirect by port(s) or "all tcp"
    ${optionalString (!cfg.ipset.enable) (
      if cfg.tcpPorts == []
      then ''
        ${iptables} -t nat -A ${natChain} -p tcp -m conntrack --ctstate NEW -j REDIRECT --to-ports ${toString cfg.listenPort}
      ''
      else
        concatStringsSep "\n" (map (p: ''
            ${iptables} -t nat -A ${natChain} -p tcp --dport ${toString p} -j REDIRECT --to-ports ${toString cfg.listenPort}
          '')
          cfg.tcpPorts)
    )}

    # Logging (rate-limited)
    ${iptables} -t nat -A ${natChain} -p tcp -m limit --limit ${cfg.logging.rateLimit} -j LOG --log-prefix "TPROXY_REDIRECT: " --log-level 4
  '';

  mkNatDetach = iface: ''
    ${iptables} -t nat -F ${natChain} 2>/dev/null || true
    ${iptables} -t nat -D PREROUTING -i ${iface} -j ${natChain} 2>/dev/null || true
    ${iptables} -t nat -X ${natChain} 2>/dev/null || true
  '';

  mkMasqueradeSetup = ''
    ${optionalString (cfg.masquerade.enable) ''
      # Add MASQUERADE for non-proxied egress
      ${iptables} -t nat -C POSTROUTING -o ${cfg.masquerade.interface} -j MASQUERADE 2>/dev/null || \
        ${iptables} -t nat -A POSTROUTING -o ${cfg.masquerade.interface} -j MASQUERADE
    ''}
  '';

  mkMasqueradeTeardown = ''
    ${optionalString (cfg.masquerade.enable) ''
      ${iptables} -t nat -D POSTROUTING -o ${cfg.masquerade.interface} -j MASQUERADE 2>/dev/null || true
    ''}
  '';

  # TPROXY path (mangle + policy routing)
  mkMangleAttachJump = iface: ''
    ${iptables} -t mangle -N ${mangleChain} 2>/dev/null || true
    ${iptables} -t mangle -C PREROUTING -i ${iface} -j ${mangleChain} 2>/dev/null || ${iptables} -t mangle -A PREROUTING -i ${iface} -j ${mangleChain}
    ${iptables} -t mangle -F ${mangleChain}
  '';

  mkMangleRules = ''
    # Skips
    ${concatStringsSep "\n" (map (cidr: ''
      ${iptables} -t mangle -A ${mangleChain} -d ${cidr} -j RETURN
    '') (cfg.excludeCidrs ++ []))}
    ${iptables} -t mangle -A ${mangleChain} -d ${cfg.v2rayAHost} -j RETURN

    # ipset scoping
    ${optionalString (cfg.ipset.enable) ''
      ${
        if cfg.tcpPorts == []
        then ''
          ${iptables} -t mangle -A ${mangleChain} -p tcp -m set --match-set ${cfg.ipset.name} dst -j TPROXY --on-port ${toString cfg.listenPort} --tproxy-mark 0x1/0x1
        ''
        else
          concatStringsSep "\n" (map (p: ''
              ${iptables} -t mangle -A ${mangleChain} -p tcp --dport ${toString p} -m set --match-set ${cfg.ipset.name} dst -j TPROXY --on-port ${toString cfg.listenPort} --tproxy-mark 0x1/0x1
            '')
            cfg.tcpPorts)
      }
    ''}

    ${optionalString (!cfg.ipset.enable) (
      if cfg.tcpPorts == []
      then ''
        ${iptables} -t mangle -A ${mangleChain} -p tcp -j TPROXY --on-port ${toString cfg.listenPort} --tproxy-mark 0x1/0x1
      ''
      else
        concatStringsSep "\n" (map (p: ''
            ${iptables} -t mangle -A ${mangleChain} -p tcp --dport ${toString p} -j TPROXY --on-port ${toString cfg.listenPort} --tproxy-mark 0x1/0x1
          '')
          cfg.tcpPorts)
    )}

    # Logging (rate-limited)
    ${iptables} -t mangle -A ${mangleChain} -p tcp -m limit --limit ${cfg.logging.rateLimit} -j LOG --log-prefix "TPROXY_MANGLE: " --log-level 4

    # Policy routing for marked packets
    ${ip} rule show | grep -q "fwmark 0x1 lookup 100" || ${ip} rule add fwmark 0x1/0x1 lookup 100
    ${ip} route show table 100 | grep -q "^local 0.0.0.0/0 dev lo" || ${ip} route add local 0.0.0.0/0 dev lo table 100
  '';

  mkMangleDetach = iface: ''
    ${iptables} -t mangle -F ${mangleChain} 2>/dev/null || true
    ${iptables} -t mangle -D PREROUTING -i ${iface} -j ${mangleChain} 2>/dev/null || true
    ${iptables} -t mangle -X ${mangleChain} 2>/dev/null || true
    ${ip} rule del fwmark 0x1/0x1 lookup 100 2>/dev/null || true
    ${ip} route del local 0.0.0.0/0 dev lo table 100 2>/dev/null || true
  '';

  # IPv6 TPROXY (optional)
  mkMangle6AttachJump = iface: ''
    ${ip6tables} -t mangle -N ${mangleChain} 2>/dev/null || true
    ${ip6tables} -t mangle -C PREROUTING -i ${iface} -j ${mangleChain} 2>/dev/null || ${ip6tables} -t mangle -A PREROUTING -i ${iface} -j ${mangleChain}
    ${ip6tables} -t mangle -F ${mangleChain}
  '';

  mkMangle6Rules = ''
    ${concatStringsSep "\n" (map (cidr: ''
        ${ip6tables} -t mangle -A ${mangleChain} -d ${cidr} -j RETURN
      '')
      cfg.ipv6.excludeCidrs)}
    ${ip6tables} -t mangle -A ${mangleChain} -d ${cfg.v2rayAHost} -j RETURN 2>/dev/null || true

    ${optionalString (cfg.ipset.enable && cfg.ipv6.enable) ''
      # If you need IPv6 ipsets, consider a separate v6 set. This example assumes v4-only ipset.
    ''}

    # Without ipset scoping for v6 (simple all tcp/ports)
    ${
      if cfg.tcpPorts == []
      then ''
        ${ip6tables} -t mangle -A ${mangleChain} -p tcp -j TPROXY --on-port ${toString cfg.listenPort} --tproxy-mark 0x1/0x1
      ''
      else
        concatStringsSep "\n" (map (p: ''
            ${ip6tables} -t mangle -A ${mangleChain} -p tcp --dport ${toString p} -j TPROXY --on-port ${toString cfg.listenPort} --tproxy-mark 0x1/0x1
          '')
          cfg.tcpPorts)
    }

    ${ip} -6 rule show | grep -q "fwmark 0x1 lookup 100" || ${ip} -6 rule add fwmark 0x1/0x1 lookup 100
    ${ip} -6 route show table 100 | grep -q "^local ::/0 dev lo" || ${ip} -6 route add local ::/0 dev lo table 100

    ${ip6tables} -t mangle -A ${mangleChain} -p tcp -m limit --limit ${cfg.logging.rateLimit} -j LOG --log-prefix "TPROXY_MANGLE6: " --log-level 4
  '';

  mkMangle6Detach = iface: ''
    ${ip6tables} -t mangle -F ${mangleChain} 2>/dev/null || true
    ${ip6tables} -t mangle -D PREROUTING -i ${iface} -j ${mangleChain} 2>/dev/null || true
    ${ip6tables} -t mangle -X ${mangleChain} 2>/dev/null || true
    ${ip} -6 rule del fwmark 0x1/0x1 lookup 100 2>/dev/null || true
    ${ip} -6 route del local ::/0 dev lo table 100 2>/dev/null || true
  '';
in {
  options.${namespace}.services.linuxTransparentProxy = {
    enable = mkBoolOpt false "Enable Linux transparent proxy helper using redsocks/v2rayA.";
    mode = mkOpt (types.enum ["redirect" "tproxy"]) "redirect" "Operating mode: NAT REDIRECT (redsocks) or true TPROXY with policy routing.";

    v2rayAHost = mkOpt types.str "192.168.89.207" "Host IP of v2rayA (SOCKS5 endpoint).";
    v2rayAPort = mkOpt types.port 1080 "Port of v2rayA SOCKS5 listener.";
    listenPort = mkOpt types.port 12345 "Local port redsocks listens on for redirected traffic.";
    interface = mkOpt types.str "enp1s0" "Ingress interface for client traffic (PREROUTING match).";
    tcpPorts = mkOpt (types.listOf types.port) [80 443] "TCP ports to redirect (set [] for all TCP).";

    ipset = {
      enable = mkBoolOpt false "Enable ipset-based scoping of destinations (redirect only for members).";
      name = mkOpt types.str "tp_desired" "Name of the ipset (inet hash:ip).";
      entries = mkOpt (types.listOf types.str) [] "List of CIDRs to add to ipset (v4).";
    };

    excludeCidrs =
      mkOpt (types.listOf types.str) defaultExcludeCidrs
      "CIDRs to always bypass the proxy (RETURN).";

    ipv6 = {
      enable = mkBoolOpt false "Enable IPv6 handling (TPROXY path only; NAT REDIRECT is v4).";
      excludeCidrs =
        mkOpt (types.listOf types.str) ["::1/128" "fc00::/7" "fe80::/10" "ff00::/8"]
        "IPv6 CIDRs to bypass when ipv6.enable = true.";
    };

    masquerade = {
      enable = mkBoolOpt false "Enable MASQUERADE for non-proxied egress (if this box is also the gateway).";
      interface = mkOpt types.str "wan0" "Egress interface used for MASQUERADE.";
    };

    logging.rateLimit = mkOpt types.str "5/second" "iptables LOG rate limit.";
  };

  config = mkIf cfg.enable (let
    usingTPROXY = cfg.mode == "tproxy";
  in {
    # Modules & sysctls
    boot.kernelModules = lib.mkIf usingTPROXY ["xt_TPROXY"];
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      # Helpful for local routing in TPROXY paths (Linux defaults are usually fine; keep here if needed)
      # "net.ipv4.conf.all.route_localnet" = 1;
    };

    # Packages
    environment.systemPackages = [pkgs.redsocks pkgs.iptables pkgs.iproute2] ++ lib.optional cfg.ipset.enable pkgs.ipset;

    # Service account
    users.groups.redsocks = {};
    users.users.redsocks = {
      isSystemUser = true;
      group = "redsocks";
    };

    # Redsocks (journald logging, no daemonize)
    systemd.services.redsocks = {
      description = "Redsocks transparent proxy helper";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.redsocks}/bin/redsocks -c ${redsocksConf cfg.mode}";
        Restart = "always";
        User = "redsocks";
        Group = "redsocks";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        # Redsocks binds high port; no CAP_NET_BIND_SERVICE needed
      };
    };

    # iptables/nft ruleset — redirect mode (NAT PREROUTING -> REDIRECT)
    systemd.services.linux-transparent-proxy-redirect = mkIf (!usingTPROXY) {
      description = "Transparent proxy setup (REDIRECT/NAT) for ${cfg.interface}";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "redsocks.service"];
      requires = ["redsocks.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "tp-redirect-setup" ''
          set -euo pipefail

          ${mkIpSetSetup}
          ${mkNatAttachJump cfg.interface}
          ${mkNatRules}
          ${mkMasqueradeSetup}
        '';
        ExecStop = pkgs.writeShellScript "tp-redirect-teardown" ''
          set -euo pipefail
          ${mkMasqueradeTeardown}
          ${mkNatDetach cfg.interface}
        '';
      };
    };

    # iptables/nft ruleset — TPROXY mode (mangle PREROUTING -> TPROXY ; policy routing)
    systemd.services.linux-transparent-proxy-tproxy = mkIf usingTPROXY {
      description = "Transparent proxy setup (TPROXY/MANGLE + policy routing) for ${cfg.interface}";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "redsocks.service"];
      requires = ["redsocks.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "tp-tproxy-setup" ''
          set -euo pipefail

          ${mkIpSetSetup}
          ${mkMangleAttachJump cfg.interface}
          ${mkMangleRules}
          ${mkMasqueradeSetup}

          ${optionalString cfg.ipv6.enable ''
            ${mkMangle6AttachJump cfg.interface}
            ${mkMangle6Rules}
          ''}
        '';
        ExecStop = pkgs.writeShellScript "tp-tproxy-teardown" ''
          set -euo pipefail
          ${mkMasqueradeTeardown}
          ${mkMangleDetach cfg.interface}
          ${optionalString cfg.ipv6.enable (mkMangle6Detach cfg.interface)}
        '';
      };
    };

    # Open local listening port for redsocks (only TCP)
    networking.firewall.allowedTCPPorts = [cfg.listenPort];

    # (Optional) If you want to keep classic file logs, you can enable your logrotate module.
    # We default to journald, so no tmpfiles/logrotate needed here.
  });
}

