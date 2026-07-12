# Route-only module (no container): exposes the herdr-remote web app and relay
# running on zanoza through Traefik at herdr.sbulav.ru / herdr-relay.sbulav.ru.
#
# Auth: Authelia only (auth-chain middleware). The relay's own token auth is
# disabled on zanoza — Authelia's session cookie is scoped to the whole
# sbulav.ru domain, so the browser sends it on the WebSocket handshake to
# the relay subdomain after logging in on the web app. Consequently the
# hosted PWA (herdr-remote.pages.dev) can NOT be used (cross-site cookies);
# use the self-hosted web app.
#
# LAN caveat: this protects only the Traefik front door. The origin ports
# on zanoza (8080/8375) remain reachable directly on the LAN without auth.
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
    enable = mkBoolOpt false "Enable Traefik routes to herdr-remote on zanoza.";
    host = mkOpt str "herdr.sbulav.ru" "The host to serve the herdr-remote web app on";
    relayHost =
      mkOpt str "herdr-relay.sbulav.ru"
        "The host to serve the herdr-remote relay (WebSocket) on";
    webUrl = mkOpt str "http://127.0.0.1:8080" "Backend URL of the herdr-remote web app";
    relayUrl = mkOpt str "http://127.0.0.1:8375" "Backend URL of the herdr-remote relay";
    mobileRelayUrl =
      mkOpt str "http://127.0.0.1:8377"
        "Backend URL of the token-authenticated native mobile relay";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "herdr-web";
      host = cfg.host;
      url = cfg.webUrl;
      route_enabled = cfg.enable;
    })
    (import ../shared/shared-traefik-bypass-route.nix {
      app = "herdr-relay-mobile";
      host = cfg.relayHost;
      url = cfg.mobileRelayUrl;
      middleware = [ "secure-headers" ];
      pathregexp = "^/native/ws$";
      route_enabled = cfg.enable;
    })
    (import ../shared/shared-traefik-route.nix {
      app = "herdr-relay";
      host = cfg.relayHost;
      url = cfg.relayUrl;
      route_enabled = cfg.enable;
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.relayHost;
      rewrite_enabled = cfg.enable;
    })
  ];
}
