{ config, lib, pkgs, namespace, ... }: let
  inherit (lib) types mkIf mkOption mkEnableOption concatStringsSep map;
  inherit (lib.${namespace}) mkBoolOpt mkOpt;
  cfg = config.${namespace}.services.linuxTransparentProxy;
in {
  options.${namespace}.services.linuxTransparentProxy = {
    enable = mkBoolOpt false "Enable Linux transparent proxy helper using redsocks";

    v2rayAHost = mkOpt types.str "192.168.89.207" "Host IP of v2rayA server";
    v2rayAPort = mkOpt types.port 1080 "Port of v2rayA SOCKS5 listener";
    listenPort = mkOpt types.port 12345 "Port for redsocks to listen on incoming redirects";
    interface = mkOpt types.str "enp1s0" "Network interface for iptables rules";
    tcpPorts = mkOpt (types.listOf types.port) [80 443] "TCP ports to redirect (set to [] for all TCP)";
  };

  config = mkIf cfg.enable {
    boot.kernelModules = [ "xt_TPROXY" ];
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    networking.firewall.allowedTCPPorts = [ cfg.listenPort ];
    environment.systemPackages = [ pkgs.redsocks pkgs.iptables ];

    users.groups.redsocks = { };
    users.users.redsocks = {
      isSystemUser = true;
      group = "redsocks";
    };

    systemd.services.redsocks = {
      description = "Redsocks transparent proxy redirector";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.redsocks}/bin/redsocks -c ${pkgs.writeText "redsocks.conf" ''
          base {
            log_debug = off;
            log_info = on;
            log = "file:/var/log/redsocks.log";
            daemon = on;
            redirector = redsocks;
          }
          redsocks {
            local_ip = 0.0.0.0;
            local_port = ${toString cfg.listenPort};
            ip = "${cfg.v2rayAHost}";
            port = ${toString cfg.v2rayAPort};
            type = socks5;
          }
        ''}";
        Restart = "always";
        User = "redsocks";
        Group = "redsocks";
      };
    };

    systemd.services.linux-transparent-proxy-iptables = {
      description = "Setup iptables for transparent proxy";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "redsocks.service" ];
      requires = [ "redsocks.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "setup-iptables" ''
          #!/bin/sh
          set -e
          ${pkgs.iptables}/bin/iptables -t nat -F PREROUTING
          ${pkgs.iptables}/bin/iptables -t mangle -F PREROUTING

          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${cfg.interface} -d 192.168.0.0/16 -j RETURN
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${cfg.interface} -s ${cfg.v2rayAHost} -j RETURN

          ${
            if cfg.tcpPorts != []
            then concatStringsSep "\n" (map (port: ''
              ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${cfg.interface} -p tcp --dport ${toString port} -j REDIRECT --to-ports ${toString cfg.listenPort}
            '') cfg.tcpPorts)
            else ''
              ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${cfg.interface} -p tcp -m conntrack --ctstate NEW -j REDIRECT --to-ports ${toString cfg.listenPort}
            ''
          }

          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${cfg.interface} -p tcp -j LOG --log-prefix "TPROXY_REDIRECT: " --log-level 4
        '';
        ExecStop = pkgs.writeShellScript "teardown-iptables" ''
          #!/bin/sh
          set -e
          ${
            if cfg.tcpPorts != []
            then concatStringsSep "\n" (map (port: ''
              ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ${cfg.interface} -p tcp --dport ${toString port} -j REDIRECT --to-ports ${toString cfg.listenPort} 2>/dev/null || true
            '') cfg.tcpPorts)
            else ''
              ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ${cfg.interface} -p tcp -m conntrack --ctstate NEW -j REDIRECT --to-ports ${toString cfg.listenPort} 2>/dev/null || true
            ''
          }
        '';
      };
    };

    systemd.tmpfiles.rules = [ "d /var/log 0755 root root - " ];

    services.logrotate.settings."redsocks" = lib.mkIf config.${namespace}.services.logrotate.enable {
      files = [ "/var/log/redsocks.log" ];
      frequency = "daily";
      rotate = 7;
      compress = true;
      copytruncate = true;
      missingok = true;
    };
  };
}