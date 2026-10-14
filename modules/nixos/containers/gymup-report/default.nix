# Route-only module (no container): serves the static GymUp training report
# from the host through Traefik.
#
# The page is built elsewhere (`./gymup` in sab's gymup working folder runs
# make_report.py and `claude -p`) and rsynced into `dataPath` as index.html, so
# the only moving part here is static-web-server bound to loopback.
#
# Auth: Authelia (default auth-chain middleware) — the report holds health data.
{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.gymup-report;
in
{
  options.${namespace}.containers.gymup-report = with types; {
    enable = mkBoolOpt false "Enable the static GymUp report site.";
    host = mkOpt str "gym.sbulav.ru" "The host to serve the GymUp report on";
    dataPath = mkOpt str "/tank/gymup-report" "Directory the report is rsynced into (owned by sab)";
    listen = mkOpt str "127.0.0.1:8790" "Loopback address static-web-server listens on";
  };

  imports = [
    (import (lib.snowfall.fs.get-file "modules/nixos/containers/shared/shared-adguard-dns-rewrite.nix")
      {
        inherit (cfg) host;
        rewrite_enabled = cfg.enable;
      }
    )
  ];

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.dataPath} 0755 sab users -" ];

    services.static-web-server = {
      enable = true;
      inherit (cfg) listen;
      root = cfg.dataPath;
      configuration = {
        general = {
          log-level = "warn";
          directory-listing = false;
          # The report is replaced in place after every workout; make the
          # browser revalidate instead of showing yesterday's page.
          cache-control-headers = false;
        };
        advanced.headers = [
          {
            source = "**";
            headers = {
              Cache-Control = "no-cache";
              X-Robots-Tag = "noindex, nofollow";
            };
          }
        ];
      };
    };

    custom.containers.traefik.routes.gymup-report = {
      inherit (cfg) host;
      url = "http://${cfg.listen}";
      # No LAN bypass route: always behind Authelia.
      middlewares = [ "auth-chain" ];
    };
  };
}
