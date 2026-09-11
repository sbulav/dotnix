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
  cfg = config.${namespace}.containers.traefik;

  # Route defaults, the rule renderer and the route assertions all live in
  # `lib/traefik` so the check can drive them without evaluating a system.
  routeDefaults = lib.custom.traefik.routeDefaults;
in
{
  options.${namespace}.containers.traefik = with types; {
    enable = mkBoolOpt false "Enable Traefik nixos-container;";
    cf_secret_file =
      mkOpt str "secrets/serverz/default.yaml"
        "SOPS secret to get cloudflare creds from";
    domain = mkOpt str "" "The domain to get certificates to";
    dataPath = mkOpt str "/tank/traefik" "Traefik data path on host machine";

    knownMiddlewares = mkOpt (listOf str) [ ] ''
      Middlewares Traefik actually defines; a route naming anything else fails
      evaluation. This module contributes the built-in set below, and a module
      that defines its own middleware appends the name here — list definitions
      concatenate, so an option default could not be extended this way.'';

    routes = mkOpt (attrsOf (
      submodule (
        { name, ... }:
        {
          options = {
            enable = mkBoolOpt routeDefaults.enable "Whether to render this route";
            # `service` is the one default that cannot come from
            # `routeDefaults`: it is the route's own name, which only the
            # submodule's `name` argument knows. `lib.custom.traefik` applies
            # the same rule from the attribute key.
            service = mkOpt str name ''
              Traefik service (backend) this router targets. Defaults to the
              router name; `allowedips-<app>` / `bypass-<app>` routers set it
              to the `<app>` service they share.'';
            host = mkOption {
              type = str;
              description = "FQDN matched by Host() — required";
            };
            url = mkOption {
              type = str;
              description = "Backend URL, http:// or https:// — required. May point at another host";
            };
            middlewares = mkOpt (listOf str) routeDefaults.middlewares "Middlewares applied to this router";
            clientIPs = mkOpt (listOf str) routeDefaults.clientIPs ''
              Source CIDRs; a non-empty list narrows the rule with ClientIP()
              alternatives.'';
            pathRegexp = mkOpt (nullOr str) routeDefaults.pathRegexp "Optional PathRegexp() narrowing the rule";
            entrypoints =
              mkOpt (listOf str) routeDefaults.entrypoints
                "Traefik entrypoints serving this router";
            certResolver = mkOpt str routeDefaults.certResolver "TLS certificate resolver";
            passHostHeader = mkBoolOpt routeDefaults.passHostHeader "Forward the original Host header to the backend";
          };
        }
      )
    )) { } "Traefik routers keyed by router name, rendered on the Traefik host";
  };

  imports = [
    # Middlewares
    ./middleware_authelia.nix
    ./middleware_allow-lan.nix
    ./middleware_secure-headers.nix
    ./middleware_secure-headers-jellyfin.nix
    ./middleware_secure-headers-opencloud.nix
    ./middleware_nextcloud-redirect.nix
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = "traefik.${cfg.domain}";
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkMerge [
    # The middlewares defined by this module and its imports.
    {
      custom.containers.traefik.knownMiddlewares = [
        "auth-chain"
        "authelia"
        "allow-lan"
        "secure-headers"
        "secure-headers-jellyfin"
        "secure-headers-opencloud"
        "nextcloud-redirect"
      ];
    }

    # Routes are validated wherever they are declared, not only on the host
    # that happens to run Traefik.
    {
      assertions = lib.custom.traefik.routeAssertions {
        inherit (cfg) routes knownMiddlewares;
      };
    }

    (mkIf cfg.enable (mkMerge [
      {
        custom.security.sops.secrets = {
          # Cloudflare environment file using template
          "traefik-cf-env" = lib.custom.secrets.containers.cloudflareEnv "traefik" // {
            sopsFile = lib.snowfall.fs.get-file "${cfg.cf_secret_file}";
          };
        };

        # Running traefik on host network, opening necessary ports
        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        containers.traefik = {
          ephemeral = true;
          autoStart = true;

          # Mounting Cloudflare creds(email and dns api token) as file
          bindMounts = {
            "${config.sops.secrets.traefik-cf-env.path}" = {
              isReadOnly = true;
            };

            "/traefik/certs" = {
              hostPath = "${cfg.dataPath}/certs/";
              isReadOnly = false;
            };
            "/traefik/logs" = {
              hostPath = "${cfg.dataPath}/logs/";
              isReadOnly = false;
            };
          };

          config = {
            #Injecting Cloudflare creds as systemd service env variables
            systemd.services.traefik.serviceConfig.EnvironmentFile = "/run/secrets/traefik-cf-env";
            services.traefik = {
              enable = true;
              staticConfigOptions = import ./staticConfigOptions.nix;

              dynamicConfigOptions = {
                http = {
                  # Dual-router pattern (same as the app containers): LAN clients hit
                  # the ClientIP router directly (longer rule wins on priority);
                  # everyone else falls through to the authelia-protected router.
                  routers.traefik-dashboard = {
                    rule = "Host(`traefik.${cfg.domain}`) && (ClientIP(`127.0.0.1/32`) || ClientIP(`172.16.64.0/24`) || ClientIP(`192.168.80.0/20`))";
                    service = "api@internal";
                    middlewares = [
                      "secure-headers"
                      "allow-lan"
                    ];
                    tls = {
                      certResolver = "production";
                      domains = {
                        "0" = {
                          main = "${cfg.domain}";
                          sans = "*.${cfg.domain}";
                        };
                      };
                    };
                  };

                  routers.traefik-dashboard-auth = {
                    rule = "Host(`traefik.${cfg.domain}`)";
                    service = "api@internal";
                    middlewares = [ "auth-chain" ];
                    tls = {
                      certResolver = "production";
                    };
                  };

                  middlewares.auth-chain = {
                    chain.middlewares = [
                      "secure-headers"
                      "authelia"
                    ];
                  };
                };
              };
            };

            # We are using Host network↲
            networking = {
              firewall.enable = false;
              useHostResolvConf = lib.mkForce false;
            };
            services.resolved = {
              enable = true;
              settings.Resolve.DNS = "172.16.64.104";
            };
            system.stateVersion = "24.11";
          };
        };
      }

      # Application routes declared through `custom.containers.traefik.routes`.
      {
        containers.traefik.config.services.traefik.dynamicConfigOptions.http =
          lib.custom.traefik.renderRoutes cfg.routes;
      }
    ]))
  ];
}
