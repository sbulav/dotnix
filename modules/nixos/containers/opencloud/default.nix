{
  config,
  lib,
  namespace,
  inputs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.opencloud;
  issuerUrl = "https://${cfg.oidcIssuerHost}";
  opencloudUrl = "https://${cfg.host}";
in
{
  options.${namespace}.containers.opencloud = with types; {
    enable = mkBoolOpt false "Enable opencloud nixos-container;";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";
    dataPath = mkOpt str "/tank/opencloud" "OpenCloud data path on host machine";
    host = mkOpt str "opencloud.sbulav.ru" "The host to serve opencloud on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.110" "With privateNetwork, which address to use in container";
    oidcIssuerHost = mkOpt str "authelia.sbulav.ru" "Hostname of the Authelia OIDC issuer";
    oidcClientId = mkOpt str "opencloud-web" "Web client ID registered in Authelia";
    adminGroup = mkOpt str "admins" "Authelia group that maps to the OpenCloud admin role";
    userGroup = mkOpt str "users" "Authelia group that maps to the OpenCloud user role";
    # POSIX driver puts each user's personal space at <posix-root>/users/<preferred_username>/.
    # Hardcoded here so external bind mounts have a stable target.
    primaryUser = mkOpt str "sab" "OpenCloud personal-space owner (must match Authelia preferred_username)";
    externalMounts = mkOpt (attrsOf str) { } "Map of <subfolder-in-personal-space> -> <hostPath> to bind into the user's personal space";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "opencloud";
      host = cfg.host;
      url = "http://${cfg.localAddress}:9200";
      route_enabled = cfg.enable;
      middleware = [ "secure-headers-opencloud" ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-opencloud" ];
      externalInterface = "ens3";
    };

    # NOTE: nixpkgs already bumps fs.inotify.max_user_watches and
    # max_user_instances to half a million each — plenty for the POSIX
    # watcher on /tank/video + /tank/torrents/download, so we don't override.

    # Pre-create the POSIX storage root *and* the per-user mountpoints on the
    # host. The container's /var/lib/opencloud is bind-mounted from this path,
    # so the directory hierarchy must already exist before nspawn attempts the
    # nested external-folder binds below. uid/gid 998 = opencloud inside the
    # container (no idmap; private_users=no).
    #
    # tmpfiles alone is not enough: systemd-nspawn auto-creates any missing
    # bind-target directory as root:root before the container starts, and on
    # subsequent restarts will not re-chown them. We additionally run a
    # oneshot before the container service to enforce ownership.
    systemd.tmpfiles.rules =
      let
        userDir = "${cfg.dataPath}/posix-storage/users/${cfg.primaryUser}";
      in
      [
        "d ${cfg.dataPath}/posix-storage          0750 998 998 -"
        "d ${cfg.dataPath}/posix-storage/users    0750 998 998 -"
        "d ${userDir}                             0750 998 998 -"
      ]
      ++ lib.mapAttrsToList (sub: _: "d ${userDir}/${sub} 0750 998 998 -") cfg.externalMounts;

    # Enforce 998:998 0750 on the posix-storage tree before each container
    # start. -R is safe here: the external bind mounts (Video, Downloads) are
    # unmounted while the container is stopped, so chown only touches the
    # OpenCloud-managed dirs and our pre-created mountpoints, never the
    # /tank/video or /tank/torrents source trees.
    systemd.services.opencloud-posix-storage-prepare = {
      description = "Ensure ownership of OpenCloud POSIX storage tree";
      wantedBy = [ "container@opencloud.service" ];
      before = [ "container@opencloud.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
      };
      script = ''
        mkdir -p ${cfg.dataPath}/posix-storage/users/${cfg.primaryUser}
        chown -R 998:998 ${cfg.dataPath}/posix-storage
        chmod -R u=rwX,g=rX,o= ${cfg.dataPath}/posix-storage
      '';
    };

    custom.security.sops.secrets = {
      "opencloud-env" = lib.custom.secrets.containers.envFileWithRestart "opencloud" // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
    };

    containers.opencloud = {
      # Non-ephemeral: the upstream NixOS module's `opencloud-init-config` oneshot
      # writes /etc/opencloud/opencloud.yaml with random internal-service secrets on
      # first run. With ephemeral=true that file (and the secrets) is regenerated on
      # every restart, invalidating IDM state and signed shares persisted in /var/lib.
      ephemeral = false;
      autoStart = true;

      privateNetwork = true;
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;

      bindMounts =
        {
          "${config.sops.secrets."opencloud-env".path}" = {
            isReadOnly = true;
          };
          "/var/lib/opencloud" = {
            hostPath = "${cfg.dataPath}";
            isReadOnly = false;
          };
        }
        # Externally-managed folders (Jellyfin libraries, torrent downloads,
        # etc.) bound *inside* the POSIX user space so OpenCloud surfaces them
        # as ordinary folders. The watcher picks up out-of-band changes via
        # inotify. uid 998 on host must have rwx on the source paths (use
        # `setfacl -R -m u:998:rwx` if the source belongs to another service).
        // lib.mapAttrs' (sub: src: {
          name = "/var/lib/opencloud/posix-storage/users/${cfg.primaryUser}/${sub}";
          value = {
            hostPath = src;
            isReadOnly = false;
          };
        }) cfg.externalMounts;

      specialArgs = {
        inherit inputs;
      };

      config =
        {
          config,
          inputs,
          pkgs,
          lib,
          ...
        }:
        let
          unstable = inputs.unstable.legacyPackages.${pkgs.system};
        in
        {
          systemd.tmpfiles.rules = [
            "d /var/lib/opencloud 0750 opencloud opencloud -"
          ];

          # The POSIX watcher invokes inotifywait as an external binary; ship it.
          # systemPackages alone is not enough — the upstream opencloud.service
          # unit runs without /run/current-system/sw/bin on PATH, so add the
          # package to the service's own PATH.
          environment.systemPackages = [ pkgs.inotify-tools ];
          systemd.services.opencloud.path = [ pkgs.inotify-tools ];

          services.opencloud = {
            enable = true;
            package = unstable.opencloud;
            webPackage = unstable.opencloud.web;
            idpWebPackage = unstable.opencloud.idp-web;

            address = cfg.localAddress;
            port = 9200;
            url = opencloudUrl;
            stateDir = "/var/lib/opencloud";
            # environmentFile is reserved for SECRETS only (OC_ADMIN_PASSWORD).
            # Non-secret config lives in `settings` (yaml) below so it stays declarative
            # and isn't silently shadowed by env entries written in sops.
            environmentFile = "/run/secrets/opencloud-env";

            # Truly global config that the upstream module reads from env across many
            # microservices. These have no clean yaml home, so they stay as env vars.
            environment = {
              OC_INSECURE = "true";
              OC_LOG_LEVEL = "info";
              OC_EXCLUDE_RUN_SERVICES = "idp";
              OC_OIDC_ISSUER = issuerUrl;
              # Traefik terminates TLS in front of us — serve plain HTTP on the
              # backend, otherwise the proxy listens with a self-signed cert and
              # Traefik logs "client sent an HTTP request to an HTTPS server".
              PROXY_TLS = "false";
              # graph service: don't fall back to default role when OIDC mapping doesn't match
              GRAPH_USERNAME_MATCH = "none";
              GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";

              # The web SPA does NOT take its client_id from config.json — it reads
              # it from the WebFinger response (property `http://opencloud.eu/ns/oidc/client_id`).
              # If unset, both config.json and WebFinger fall back to the upstream
              # default "web" with scope "openid profile email", which Authelia
              # rejects as "invalid_client". The env vars below propagate to both.
              WEB_OIDC_CLIENT_ID = cfg.oidcClientId;
              WEB_OIDC_SCOPE = "openid profile email groups offline_access";
              WEB_OIDC_METADATA_URL = "${issuerUrl}/.well-known/openid-configuration";

              # POSIX storage driver: files live as plain files under
              # /var/lib/opencloud/posix-storage/users/<username>/, so /tank/video
              # and friends bind-mounted under there appear natively in OpenCloud
              # while still being usable by Jellyfin/torrent client/etc.
              # Caveat: the decomposed default layout at
              # /var/lib/opencloud/storage/users/ is left untouched but unused
              # after this switch — fine while OpenCloud is empty; clean up
              # /tank/opencloud/storage if you want the disk back.
              STORAGE_USERS_DRIVER = "posix";
              STORAGE_USERS_ID_CACHE_STORE = "nats-js-kv";
              STORAGE_USERS_POSIX_ROOT = "/var/lib/opencloud/posix-storage";
              STORAGE_USERS_POSIX_WATCH_FS = "true";
              STORAGE_USERS_POSIX_WATCH_PATH = "/var/lib/opencloud/posix-storage";
              STORAGE_USERS_POSIX_WATCH_TYPE = "inotifywait";
            };

            settings = {
              proxy = {
                auto_provision_accounts = true;
                user_oidc_claim = "preferred_username";
                user_cs3_claim = "username";
                csp_config_file_location = "/etc/opencloud/csp.yaml";

                oidc = {
                  rewrite_well_known = true;
                  access_token_verify_method = "none";
                };

                role_assignment = {
                  driver = "oidc";
                  oidc_role_mapper = {
                    role_claim = "groups";
                    role_mapping = [
                      {
                        role_name = "admin";
                        claim_value = cfg.adminGroup;
                      }
                      {
                        role_name = "user";
                        claim_value = cfg.userGroup;
                      }
                    ];
                  };
                };
              };

              web.web.config.oidc = {
                client_id = cfg.oidcClientId;
                scope = "openid profile email groups offline_access";
                metadata_url = "${issuerUrl}/.well-known/openid-configuration";
              };

              csp = {
                directives = {
                  child-src = [ "'self'" ];
                  connect-src = [
                    "'self'"
                    "blob:"
                    "${issuerUrl}/"
                    "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                    "https://update.opencloud.eu/"
                  ];
                  default-src = [ "'none'" ];
                  font-src = [ "'self'" ];
                  frame-ancestors = [ "'self'" ];
                  frame-src = [
                    "'self'"
                    "blob:"
                    "${issuerUrl}/"
                    "https://docs.opencloud.eu"
                  ];
                  img-src = [
                    "'self'"
                    "data:"
                    "blob:"
                    "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                  ];
                  manifest-src = [ "'self'" ];
                  media-src = [ "'self'" ];
                  object-src = [
                    "'self'"
                    "blob:"
                  ];
                  script-src = [
                    "'self'"
                    "'unsafe-inline'"
                    "${issuerUrl}/"
                  ];
                  style-src = [
                    "'self'"
                    "'unsafe-inline'"
                  ];
                  worker-src = [
                    "'self'"
                    "blob:"
                  ];
                };
              };
            };
          };

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [ 9200 ];
            };
            useHostResolvConf = lib.mkForce false;
          };

          services.resolved = {
            enable = true;
            extraConfig = ''
              DNS=172.16.64.104
            '';
          };

          system.stateVersion = "25.11";
        };
    };
  };
}
