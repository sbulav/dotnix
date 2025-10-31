{
  pkgs,
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.v2raya;
in
{
  options.${namespace}.containers.v2raya = with types; {
    enable = mkBoolOpt false "Enable v2raya nixos-container;";
    dataPath = mkOpt str "/tank/v2raya" "v2raya data path on host machine";
    host = mkOpt str "v2raya.sbulav.ru" "The host to serve v2raya on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.108" "With privateNetwork, which address to use in container";
  };
  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "v2raya";
      host = cfg.host;
      url = "http://${cfg.localAddress}:2017";
      route_enabled = cfg.enable;
      middlewares = [
        "secure-headers"
        "allow-lan"
      ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-v2raya" ];
      externalInterface = "ens3";
    };

    containers.v2raya = {
      ephemeral = true;
      autoStart = true;
      enableTun = true;

      # Mounting Cloudflare creds(email and dns api token) as file
      bindMounts = {
        "/var/log/v2raya/" = {
          hostPath = "${cfg.dataPath}/logs/";
          isReadOnly = false;
        };
        "/etc/v2raya" = {
          hostPath = "${cfg.dataPath}/config";
          isReadOnly = false;
        };
      };
      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      forwardPorts = [
        {
          containerPort = 20170;
          hostPort = 20170;
          protocol = "tcp";
        }
        {
          containerPort = 20172;
          hostPort = 20172;
          protocol = "tcp";
        }
      ];
      config =
        { ... }:
        {
          services.v2raya = {
            enable = true;
            cliPackage = pkgs.xray;
          };
          networking = {
            firewall = {
              enable = false;
              allowedTCPPorts = [
                2017
                20170
                20172
              ];
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
