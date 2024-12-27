{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.immich;
in {
  options.${namespace}.containers.immich = with types; {
    enable = mkBoolOpt false "Enable Immich nixos-container;";
    dataPath = mkOpt str "/tank/immich" "Immich data path on host machine";
    host = mkOpt str "immich.sbulav.ru" "The host to serve Immich on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.109" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/serverz/default.yaml" "SOPS secret to get creds from";
  };
  imports = [
    # TODO: fix this workaround for accessing mobile devices
    # https://github.com/immich-app/immich/discussions/3118
    (import ../shared/shared-traefik-bypass-route.nix
      {
        app = "immich";
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:2283";
        route_enabled = cfg.enable;
        middleware = ["secure-headers"];
        pathregexp = "/api/(albums|users|partners)|/api/.well-known/immich|^/api/(auth|oauth|socket.io|sync|assets|server)/";
      })
    (import ../shared/shared-traefik-route.nix
      {
        app = "immich";
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:2283";
        route_enabled = cfg.enable;
      })
    (import ../shared/shared-adguard-dns-rewrite.nix
      {
        host = "${cfg.host}";
        rewrite_enabled = cfg.enable;
      })
  ];

  config = mkIf cfg.enable {
    sops.secrets = {
      immich_config = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 999;
      };
    };
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-immich"];
      externalInterface = "ens3";
    };
    containers.immich = {
      ephemeral = true;
      autoStart = true;

      bindMounts = {
        "${config.sops.secrets.immich_config.path}" = {
          isReadOnly = true;
        };
        "/var/lib/immich/" = {
          hostPath = "${cfg.dataPath}/";
          isReadOnly = false;
        };
        "/var/lib/postgresql/" = {
          hostPath = "${cfg.dataPath}/postgresql";
          isReadOnly = false;
        };
        "/photos" = {
          hostPath = "/tank/photos/";
          isReadOnly = false;
        };
      };
      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      config = {...}: {
        systemd.tmpfiles.rules = [
          "d /var/lib/immich 750 immich immich -"
          "d /var/lib/postgresql 700 postgres postgres -"
        ];

        services.immich = {
          enable = true;
          host = "${cfg.localAddress}";
          mediaLocation = "/var/lib/immich";
          # Setting settings to null to inject oidc config with client secret from sops
          settings = null;
          environment = {
            IMMICH_ENV = "production";
            IMMICH_TRUSTED_PROXIES = "${cfg.hostAddress}";
            IMMICH_CONFIG_FILE = "${config.sops.secrets."immich_config".path}";
          };
        };

        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [2283];
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
