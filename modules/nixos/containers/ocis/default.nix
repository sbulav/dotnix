{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.ocis;
in {
  options.${namespace}.containers.ocis = with types; {
    enable = mkBoolOpt false "Enable ocis nixos-container;";
    dataPath = mkOpt str "/tank/ocis" "ocis data path on host machine";
    host = mkOpt str "ocis.sbulav.ru" "The host to serve ocis on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.111" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/serverz/default.yaml" "SOPS secret to get creds from";
  };
  imports = [
    (import ../shared/shared-traefik-route.nix
      {
        app = "ocis";
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:9200";
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
      internalInterfaces = ["ve-ocis"];
      externalInterface = "ens3";
    };
    containers.ocis = {
      ephemeral = true;
      autoStart = true;

      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      config = {...}: {
        services.ocis = {
          package = pkgs.ocis-bin-patched;
          enable = true;
          url = "${cfg.host}";
          address = "${cfg.localAddress}";
          # https://github.com/owncloud/ocis/blob/master/deployments/examples/ocis_hello/docker-compose.yml
          environment = {
            GATEWAY_STORAGE_USERS_MOUNT_ID = "998";
            OCIS_INSECURE = "false";
            OCIS_INSECURE_BACKENDS = "true";
            OCIS_JWT_SECRET = "super_secret";
            OCIS_LDAP_BIND_PASSWORD = "password";
            OCIS_LOG_LEVEL = "error";
            OCIS_MACHINE_AUTH_API_KEY = "foo";
            OCIS_MOUNT_ID = "998";
            OCIS_SERVICE_ACCOUNT_ID = "foo";
            OCIS_SERVICE_ACCOUNT_SECRET = "foo";
            OCIS_STORAGE_USERS_MOUNT_ID = "998";
            OCIS_SYSTEM_USER_API_KEY = "foo";
            OCIS_SYSTEM_USER_ID = "998";
            OCIS_TRANSFER_SECRET = "foo";
            PROXY_TLS = "false"; # do not use SSL between Traefik and oCIS
            STORAGE_USERS_MOUNT_ID = "998";
            CS3_ALLOW_INSECURE = "true";
            GRAPH_APPLICATION_ID = "1234";
            IDM_IDPSVC_PASSWORD = "password";
            IDM_REVASVC_PASSWORD = "password";
            IDM_SVC_PASSWORD = "password";
            IDP_ISS = "https://localhost:9200";
            IDP_TLS = "false";
            TLS_INSECURE = "true";
            TLS_SKIP_VERIFY_CLIENT_CERT = "true";
            WEBDAV_ALLOW_INSECURE = "true";
          };
        };

        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [9200];
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
