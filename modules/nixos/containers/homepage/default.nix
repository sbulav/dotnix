{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.homepage;
in {
  options.${namespace}.containers.homepage = with types; {
    enable = mkBoolOpt false "Enable homepage nixos-container;";
    host = mkOpt str "homepage.sbulav.ru" "The host to serve homepage on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.101" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix
      {
        app = "homepage";
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:8082";
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
      "homepage-env" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
    };
    containers.homepage = {
      ephemeral = true;
      autoStart = true;

      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      bindMounts = {
        "${config.sops.secrets."homepage-env".path}" = {
          isReadOnly = true;
        };
      };

      config = {...}: {
        networking.hosts = {
          #TODO: remove this once migrated
          "${cfg.hostAddress}" = [
            "traefik.sbulav.ru"
            "adguard.sbulav.ru"
            "flood.sbulav.ru"
            "jellyfin.sbulav.ru"
          ];
        };

        services.homepage-dashboard = {
          environmentFile = config.sops.secrets.homepage-env.path;
          enable = true;
          widgets = [
            {
              resources = {
                cpu = true;
                disk = "/";
                memory = true;
              };
            }
          ];
          services = [
            {
              "Network" = [
                # TODO: implement enabling widgets based on config
                {
                  "Traefik" = {
                    icon = "traefik";
                    href = "https://traefik.${config.${namespace}.containers.traefik.domain}";
                    widget = {
                      type = "traefik";
                      url = "https://traefik.${config.${namespace}.containers.traefik.domain}";
                    };
                  };
                }
                {
                  "Adguard" = mkIf config.${namespace}.containers.adguard.enable {
                    icon = "adguard-home";
                    href = "https://${config.${namespace}.containers.adguard.host}";
                    widget = {
                      type = "adguard";
                      url = "http://${config.${namespace}.containers.adguard.localAddress}:3000";
                    };
                  };
                }
              ];
            }
            {
              "Media" = [
                {
                  "nextcloud" = mkIf config.${namespace}.containers.nextcloud.enable {
                    icon = "nextcloud";
                    href = "https://${config.${namespace}.containers.nextcloud.host}";
                    widget = {
                      type = "nextcloud";
                      key = "{{HOMEPAGE_VAR_NEXTCLOUD_API_KEY}}";
                      url = "http://${config.${namespace}.containers.nextcloud.localAddress}:80";
                    };
                  };
                }

                {
                  "jellyfin" = mkIf config.${namespace}.containers.jellyfin.enable {
                    icon = "jellyfin";
                    href = "https://${config.${namespace}.containers.jellyfin.host}";
                    widget = {
                      type = "jellyfin";
                      key = "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}";
                      url = "http://${config.${namespace}.containers.jellyfin.localAddress}:8096";
                      enableBlocks = true; # optional, defaults to false
                      enableNowPlaying = true; # optional, defaults to true
                      enableUser = true; # optional, defaults to false
                      showEpisodeNumber = true; # optional, defaults to false
                      expandOneStreamToTwoRows = false; # optional, defaults to true
                    };
                  };
                }
              ];
            }
            {
              "ARR Stack" = [
                {
                  "Flood" = mkIf config.${namespace}.containers.flood.enable {
                    icon = "flood";
                    href = "https://${config.${namespace}.containers.flood.host}";
                    widget = {
                      type = "flood";
                      url = "http://${config.${namespace}.containers.flood.localAddress}:3000";
                    };
                  };
                }
              ];
            }
          ];
        };

        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [8082];
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
