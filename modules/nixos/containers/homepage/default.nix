{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  householdDnsSettings = lib.custom.dns.resolvedSettings;
  cfg = config.${namespace}.containers.homepage;
  ctr = config.${namespace}.containers;
  # A dashboard entry exists only while its service's container is enabled;
  # mkIf can't do this, the services option leaves a disabled one as {}.
  entry =
    svc: name: value:
    optional ctr.${svc}.enable { ${name} = value; };
  # Drop a group whose entries are all disabled instead of rendering it empty.
  group = name: entries: optional (entries != [ ]) { ${name} = entries; };
in
{
  options.${namespace}.containers.homepage = with types; {
    enable = mkBoolOpt false "Enable homepage nixos-container;";
    host = mkOpt str "homepage.sbulav.ru" "The host to serve homepage on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.101" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";
  };

  imports = [
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = "${cfg.host}";
      rewrite_enabled = cfg.enable;
    })
  ];
  config = mkIf cfg.enable {
    custom.containers.traefik.routes = {
      homepage = {
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:8082";
      };
      "allowedips-homepage" = {
        service = "homepage";
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:8082";
        middlewares = [
          "secure-headers"
          "allow-lan"
        ];
        clientIPs = [
          "172.16.64.0/24"
          "192.168.80.0/20"
        ];
      };
    };

    custom.security.sops.secrets = {
      # Environment file using template
      "homepage-env" = lib.custom.secrets.containers.envFileWithRestart "homepage" // {
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

      config = _: {
        services.homepage-dashboard = {
          environmentFiles = [ config.sops.secrets.homepage-env.path ];
          enable = true;
          widgets = [
            {
              resources = {
                cpu = true;
                cputemp = true;
                disk = [ "/" ];
                memory = true;
              };
            }
          ];
          services =
            group "Network" (
              entry "traefik" "Traefik" {
                icon = "traefik";
                href = "https://traefik.${ctr.traefik.domain}";
                widget = {
                  type = "traefik";
                  url = "https://traefik.${ctr.traefik.domain}";
                };
              }
              ++ entry "adguard" "Adguard" {
                icon = "adguard-home";
                href = "https://${ctr.adguard.host}";
                widget = {
                  type = "adguard";
                  url = "http://${ctr.adguard.localAddress}:3000";
                };
              }
            )
            ++ group "Media" (
              entry "jellyfin" "jellyfin" {
                icon = "jellyfin";
                href = "https://${ctr.jellyfin.host}";
                widget = {
                  type = "jellyfin";
                  key = "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}";
                  url = "http://${ctr.jellyfin.localAddress}:8096";
                  enableBlocks = true; # optional, defaults to false
                  enableNowPlaying = true; # optional, defaults to true
                  enableUser = true; # optional, defaults to false
                  showEpisodeNumber = true; # optional, defaults to false
                  expandOneStreamToTwoRows = false; # optional, defaults to true
                };
              }
              ++ entry "immich" "immich" {
                icon = "immich";
                href = "https://${ctr.immich.host}";
                widget = {
                  type = "immich";
                  version = 2;
                  key = "{{HOMEPAGE_VAR_IMMICH_API_KEY}}";
                  url = "http://${ctr.immich.localAddress}:2283";
                };
              }
              ++ entry "opencloud" "opencloud" {
                icon = "opencloud";
                href = "https://${ctr.opencloud.host}";
              }
            )
            ++ group "ARR Stack" (
              entry "flood" "Flood" {
                icon = "flood";
                href = "https://${ctr.flood.host}";
                widget = {
                  type = "flood";
                  url = "http://${ctr.flood.localAddress}:3000";
                };
              }
            );
        };

        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [ 8082 ];
          };
          useHostResolvConf = lib.mkForce false;
        };

        services.resolved = {
          enable = true;
          settings.Resolve = householdDnsSettings;
        };
        system.stateVersion = "24.11";
      };
    };
  };
}
