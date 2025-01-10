{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.cockpit;
in {
  options.${namespace}.containers.cockpit = with types; {
    enable = mkBoolOpt false "Enable Cockpit server monitoring;";
    host = mkOpt str "cockpit.sbulav.ru" "The host to serve flood on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.111" "With privateNetwork, which address to use in container";
  };
  imports = [
    (import ../shared/shared-traefik-route.nix
      {
        app = "cockpit";
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:9090";
        route_enabled = cfg.enable;
      })
    (import ../shared/shared-adguard-dns-rewrite.nix
      {
        host = "${cfg.host}";
        rewrite_enabled = cfg.enable;
      })
  ];

  config = mkIf cfg.enable {
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-cockpit"];
      externalInterface = "ens3";
    };
    containers.cockpit = {
      ephemeral = true;
      autoStart = true;

      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      forwardPorts = [
        {
          containerPort = 9090;
          hostPort = 9090;
          protocol = "tcp";
        }
      ];
      config = {...}: {
        services.cockpit = {
          enable = true;
          settings = {
            WebService = {
              # Origins = "https://${cfg.host}";
              # ProtocolHeader = "X-Forwarded-Proto";
              AllowUnencrypted = true;
            };
          };
        };

        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [9090];
          };
          # Use systemd-resolved inside the container
          # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
          useHostResolvConf = lib.mkForce false;
        };
        services.resolved.enable = true;
        system.stateVersion = "24.11";
      };
    };
  };
}
