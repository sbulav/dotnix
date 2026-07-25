# Not working for now
{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.seafile;
in
{
  options.${namespace}.containers.seafile = with types; {
    enable = mkBoolOpt false "Enable seafile nixos-container;";
    dataPath = mkOpt str "/tank/seafile" "seafile data path on host machine";
    host = mkOpt str "seafile.sbulav.ru" "The host to serve seafile on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.110" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/serverz/default.yaml" "SOPS secret to get creds from";
  };
  imports = [
    # # TODO: fix this workaround for accessing mobile devices
    (import ../shared/shared-traefik-bypass-route.nix {
      app = "seafile";
      host = "${cfg.host}";
      url = "http://${cfg.localAddress}:8082";
      route_enabled = cfg.enable;
      middleware = [ "allow-lan" ];
      pathregexp = "^/seafhttp";
    })
    (import ../shared/shared-traefik-route.nix {
      app = "seahub";
      host = "${cfg.host}";
      url = "http://${cfg.localAddress}:8083";
      middleware = [ "allow-lan" ];
      route_enabled = cfg.enable;
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = "${cfg.host}";
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    # sops.secrets = {
    #   seafile_config = {
    #     sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
    #     uid = 999;
    #   };
    # };
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-seafile" ];
      externalInterface = "ens3";
    };
    containers.seafile = {
      ephemeral = true;
      autoStart = true;

      # bindMounts = {
      #   "${config.sops.secrets.seafile_config.path}" = {
      #     isReadOnly = true;
      #   };
      #   "/var/lib/seafile/" = {
      #     hostPath = "${cfg.dataPath}/";
      #     isReadOnly = false;
      #   };
      #   "/var/lib/postgresql/" = {
      #     hostPath = "${cfg.dataPath}/postgresql";
      #     isReadOnly = false;
      #   };
      #   "/photos" = {
      #     hostPath = "/tank/photos/";
      #     isReadOnly = false;
      #   };
      # };
      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";
      # https://github.com/jz8132543/flakes/blob/7ded5a300662dc1a87b482da392d632b0e22528e/nixos/modules/services/seafile.nix#L19
      config =
        { ... }:
        {
          services.seafile = {
            enable = true;
            adminEmail = config.${namespace}.user.email;
            initialAdminPassword = "password";
            seahubAddress = "${cfg.localAddress}:8083";
            ccnetSettings.General.SERVICE_URL = "${cfg.host}";
            # seafileSettings = {
            #   fileserver = {
            #     port = 8082;
            #     host = "ipv4:${cfg.localAddress}";
            #   };
            # };
            seahubExtraConf = ''
              DEBUG = True
              CSRF_TRUSTED_ORIGINS = ["https://${cfg.host}", "http://127.0.0.1", "http://${cfg.localAddress}"]
              FILE_SERVER_ROOT = "https://${cfg.host}/seafhttp"
            '';
          };

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [
                8082
                8083
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
