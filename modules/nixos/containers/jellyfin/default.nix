{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.jellyfin;
in
{
  options.${namespace}.containers.jellyfin = with types; {
    enable = mkBoolOpt false "Enable jellyfin nixos-container;";
    host = mkOpt str "jellyfin.sbulav.ru" "The host to serve jellyfin on";
    dataPath = mkOpt str "/tank/jellyfin" "Jellyfin data path on host machine";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.107" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/serverz/default.yaml" "SOPS secret to get creds from";
    enableGPU = mkBoolOpt false "Enable GPU device passthrough for hardware video acceleration";
    # Read-only view of the arr-stack library (issue #39). Empty = no mount.
    arrLibraryPath = mkOpt str "" "Host path of the arr media library to bind read-only";
    # zanoza's uplink DNS-poisons RKN-blocked metadata hosts (TMDB). .NET
    # honours HTTP(S)_PROXY, so point Jellyfin at sing-box's mixed inbound.
    httpProxy =
      mkOpt str ""
        "HTTP proxy URL for Jellyfin's outbound requests (metadata, plugins); empty = direct";
    # Libraries with realtime monitoring off (IPCAM: thousands of jpgs a day
    # made the inotify watcher burn a core) are re-scanned from the host on a
    # timer instead. Needs the "jellyfin/api_key" secret in secret_file.
    scheduledScan = {
      libraries = mkOpt (listOf str) [ ] "Jellyfin library names to refresh on the timer";
      onCalendar = mkOpt str "*:0/15" "systemd OnCalendar expression for the library refresh";
    };
  };
  imports = [
    (import ../shared/shared-traefik-clientip-route.nix {
      app = "jellyfin";
      host = cfg.host;
      url = "http://${cfg.localAddress}:8096";
      route_enabled = cfg.enable;
      middleware = [
        "secure-headers-jellyfin"
        "allow-lan"
      ];
      clientips = "ClientIP(`172.16.64.0/24`) || ClientIP(`192.168.80.0/20`)";
    })
    (import ../shared/shared-traefik-route.nix {
      app = "jellyfin";
      host = cfg.host;
      url = "http://${cfg.localAddress}:8096";
      route_enabled = cfg.enable;
      middleware = [
        "secure-headers-jellyfin"
        "authelia"
      ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = "${cfg.host}";
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    custom.security.sops.secrets = {
      # OIDC client secret using standard template
      "jellyfin/oidc_client_secret" = lib.custom.secrets.containers.oidcClientSecret "jellyfin" // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
    }
    // lib.optionalAttrs (cfg.scheduledScan.libraries != [ ]) {
      # Host-side only (read by the refresh timer below), not bind-mounted.
      "jellyfin/api_key" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
    };

    systemd.services.jellyfin-library-refresh = mkIf (cfg.scheduledScan.libraries != [ ]) {
      description = "Refresh selected Jellyfin libraries";
      after = [ "container@jellyfin.service" ];
      requisite = [ "container@jellyfin.service" ];
      path = with pkgs; [
        curl
        jq
      ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        LoadCredential = "api_key:${config.sops.secrets."jellyfin/api_key".path}";
      };
      script = ''
        base="http://${cfg.localAddress}:8096"
        auth="Authorization: MediaBrowser Token=$(cat "$CREDENTIALS_DIRECTORY/api_key")"
        folders=$(curl -sSf -m 30 -H "$auth" "$base/Library/VirtualFolders")
        for name in ${lib.escapeShellArgs cfg.scheduledScan.libraries}; do
          id=$(jq -r --arg n "$name" '.[] | select(.Name == $n) | .ItemId' <<<"$folders")
          if [ -z "$id" ]; then
            echo "library '$name' not found" >&2
            continue
          fi
          curl -sSf -m 30 -o /dev/null -X POST -H "$auth" \
            "$base/Items/$id/Refresh?Recursive=true&ImageRefreshMode=Default&MetadataRefreshMode=Default&ReplaceAllImages=false&ReplaceAllMetadata=false"
          echo "refresh requested: $name ($id)"
        done
      '';
    };
    systemd.timers.jellyfin-library-refresh = mkIf (cfg.scheduledScan.libraries != [ ]) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.scheduledScan.onCalendar;
        RandomizedDelaySec = "1m";
        Persistent = true;
      };
    };
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-jellyfin" ];
      externalInterface = "enp3s0";
    };
    containers.jellyfin = {
      ephemeral = true;
      autoStart = true;

      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";
      forwardPorts = [
        {
          containerPort = 8096;
          hostPort = 8096;
          protocol = "tcp";
        }
      ];

      allowedDevices = [
        {
          node = "/dev/dri/renderD128";
          modifier = "rw";
        }
      ];
      bindMounts = {
        "${config.sops.secrets."jellyfin/oidc_client_secret".path}" = {
          isReadOnly = true;
        };
        "/var/lib/jellyfin/config/" = {
          hostPath = "${cfg.dataPath}/config/";
          isReadOnly = false;
        };
        "/var/lib/jellyfin/" = {
          hostPath = "${cfg.dataPath}/";
          isReadOnly = false;
        };
        "/var/lib/jellyfin/log/" = {
          "hostPath" = "${cfg.dataPath}/log/";
          isReadOnly = false;
        };
        "/var/lib/jellyfin/video/" = {
          "hostPath" = "/tank/video/";
          isReadOnly = false;
        };
        "/var/lib/jellyfin/video/ipcam" = {
          "hostPath" = "/tank/ipcam";
          isReadOnly = false;
        };
      }
      // lib.optionalAttrs (cfg.arrLibraryPath != "") {
        "/var/lib/jellyfin/media" = {
          hostPath = cfg.arrLibraryPath;
          isReadOnly = true;
        };
      }
      // lib.optionalAttrs cfg.enableGPU {
        "/dev/dri" = {
          hostPath = "/dev/dri";
          isReadOnly = false;
        };
      };

      config =
        { pkgs, ... }:
        {

          # Provides /run/opengl-driver/lib/dri (radeonsi_drv_video.so) for VAAPI.
          hardware.graphics.enable = true;
          systemd.tmpfiles.rules = [
            "d /var/lib/jellyfin 700 jellyfin jellyfin -"
          ];

          environment.systemPackages = lib.optionals cfg.enableGPU [
            pkgs.libva-utils # vainfo, for debugging
          ];

          services.jellyfin = {
            enable = true;
            # The container is ephemeral (tmpfs root): keep the image cache
            # and the transcode dir on the persistent bind mount instead.
            cacheDir = "/var/lib/jellyfin/cache";
          };

          # Add jellyfin user to video/render groups for device access
          users.users.jellyfin.extraGroups = lib.optionals cfg.enableGPU [
            "video"
            "render"
          ];

          systemd.services.jellyfin = lib.mkMerge [
            (lib.mkIf cfg.enableGPU {
              environment = {
                LIBVA_DRIVER_NAME = "radeonsi";
                LIBVA_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";
                # jellyfin's home is /var/empty; without this RADV cannot
                # write its shader cache and recompiles on every transcode.
                XDG_CACHE_HOME = "/var/lib/jellyfin/cache";
              };
            })
            (lib.mkIf (cfg.httpProxy != "") {
              environment = {
                HTTP_PROXY = cfg.httpProxy;
                HTTPS_PROXY = cfg.httpProxy;
                # .NET no_proxy: hostnames and ".suffix" only, no CIDR.
                NO_PROXY = "localhost,127.0.0.1,${cfg.hostAddress},.sbulav.ru";
              };
            })
            {
              preStart =
                let
                  sso-authentication-plugin = pkgs.fetchzip {
                    stripRoot = false;
                    url = "https://github.com/9p4/jellyfin-plugin-sso/releases/download/v4.0.0.3/sso-authentication_4.0.0.3.zip";
                    hash = "sha256-Jkuc+Ua7934iSutf/zTY1phTxaltUkfiujOkCi7BW8w=";
                  };
                  ssoConfig = pkgs.writeTextFile {
                    name = "SSO-Auth.xml";
                    text = ''
                      <?xml version="1.0" encoding="utf-8"?>
                      <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                        <SamlConfigs />
                        <OidConfigs>
                          <item>
                            <key>
                              <string>authelia</string>
                            </key>
                            <value>
                              <PluginConfiguration>
                                <OidEndpoint>https://${config.${namespace}.containers.authelia.host}</OidEndpoint>
                                <OidClientId>jellyfin</OidClientId>
                                <OidSecret>CLIENT_SECRET_REPLACE</OidSecret>
                                <Enabled>true</Enabled>
                                <EnableAuthorization>true</EnableAuthorization>
                                <EnableAllFolders>true</EnableAllFolders>
                                <EnabledFolders />
                                <AdminRoles>
                                  <string>jellyfin-admins</string>
                                  <string>admins</string>
                                </AdminRoles>
                                <Roles>
                                  <string>jellyfin-users</string>
                                  <string>dev</string>
                                </Roles>
                                <EnableFolderRoles>false</EnableFolderRoles>
                                <EnableLiveTvRoles>false</EnableLiveTvRoles>
                                <EnableLiveTv>false</EnableLiveTv>
                                <EnableLiveTvManagement>false</EnableLiveTvManagement>
                                <LiveTvRoles />
                                <LiveTvManagementRoles />
                                <FolderRoleMappings />
                                <RoleClaim>groups</RoleClaim>
                                <OidScopes>
                                  <string>groups</string>
                                </OidScopes>
                                <CanonicalLinks></CanonicalLinks>
                                <DisableHttps>false</DisableHttps>
                                <DisablePushedAuthorization>true</DisablePushedAuthorization>
                                <DoNotValidateEndpoints>false</DoNotValidateEndpoints>
                                <DoNotValidateIssuerName>false</DoNotValidateIssuerName>
                              </PluginConfiguration>
                            </value>
                          </item>
                        </OidConfigs>
                      </PluginConfiguration>
                    '';
                    executable = false;
                  };

                  brandingConfig = pkgs.writeTextFile {
                    name = "brandingConfig.xml";
                    text = ''
                      <?xml version="1.0" encoding="utf-8"?>
                      <BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                        <LoginDisclaimer>&lt;form action="https://${cfg.host}/sso/OID/start/authelia"&gt;
                        &lt;button class="raised block emby-button button-submit"&gt;
                          Sign in with SSO
                        &lt;/button&gt;
                      &lt;/form&gt;</LoginDisclaimer>
                        <CustomCss>a.raised.emby-button {
                        padding: 0.9em 1em;
                        color: inherit !important;
                      }

                      .disclaimerContainer {
                        display: block;
                      }</CustomCss>
                        <SplashscreenEnabled>true</SplashscreenEnabled>
                      </BrandingOptions>
                    '';
                    executable = false;
                  };
                in
                ''
                  # Setting up SSO integration
                  mkdir -p /var/lib/jellyfin/plugins/configurations
                  CLIENT_SECRET="$(cat ${config.sops.secrets."jellyfin/oidc_client_secret".path})"
                  sed "s/CLIENT_SECRET_REPLACE/$CLIENT_SECRET/" ${ssoConfig} > /var/lib/jellyfin/plugins/configurations/SSO-Auth.xml
                  cat ${brandingConfig} > /var/lib/jellyfin/config/branding.xml

                  # Setting up SSO plugin
                  rm -rf /var/lib/jellyfin/plugins/sso-authentication-plugin
                  mkdir -p /var/lib/jellyfin/plugins/sso-authentication-plugin
                  cp ${sso-authentication-plugin}/* /var/lib/jellyfin/plugins/sso-authentication-plugin/
                  chmod -R 770 /var/lib/jellyfin/plugins/sso-authentication-plugin
                '';
            }
          ];

          networking = {
            # hosts = {
            #   #TODO: remove this once migrated
            #   "${cfg.hostAddress}" = [
            #     "authelia.sbulav.ru"
            #   ];
            # };
            firewall = {
              enable = true;
              # https://jellyfin.org/docs/general/networking/index.html#port-bindings
              allowedTCPPorts = [
                8096
                8920
              ];
              allowedUDPPorts = [
                1900
                7359
              ];
            };
            useHostResolvConf = lib.mkForce false;
          };

          services.resolved = {
            enable = true;
            settings.Resolve.DNS = "172.16.64.104";
          };
          system.stateVersion = "24.11";
        };
    };
  };
}
