# Same-origin route from Traefik to the loopback Herdr Remote browser service.
{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.herdr-remote;
in
{
  options.${namespace}.containers.herdr-remote = with types; {
    enable = mkBoolOpt false "Enable the authenticated Herdr Remote route on zanoza.";
    host = mkOpt str "herdr.sbulav.ru" "Host serving the Herdr Remote PWA and browser API";
    backendUrl = mkOpt str "http://127.0.0.1:8080" "Loopback URL of the Herdr Remote browser service";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "herdr-remote";
      host = cfg.host;
      url = cfg.backendUrl;
      middleware = [
        "auth-chain"
        "herdr-oidc-identity"
      ];
      route_enabled = cfg.enable;
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf (cfg.enable && config.${namespace}.containers.traefik.enable) {
    # This middleware runs after auth-chain. customRequestHeaders replaces any
    # client-supplied values, so spoofed identity headers cannot reach Herdr.
    containers.traefik.config.services.traefik.dynamicConfigOptions.http.middlewares.herdr-oidc-identity =
      {
        headers.customRequestHeaders = {
          X-OIDC-Issuer = "https://authelia.sbulav.ru";
          X-OIDC-Audience = "herdr-remote";
          X-OIDC-Subject = "sab";
          X-OIDC-Assurance = "two_factor";
        };
      };
  };
}
