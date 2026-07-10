# herdr-remote: monitor and control herdr agents from a phone browser
# on the LAN (https://github.com/dcolinmorgan/herdr-remote).
#
# Two manual-start systemd user services (no autostart, like herdr itself):
#   systemctl --user start herdr-relay   # WebSocket relay on :8375
#   systemctl --user start herdr-web     # static web app on :8080
# Phone: open http://<host>:8080, enter ws://<host>:8375 as relay URL.
#
# Notes / accepted risks (v1, LAN-only):
# - No auth token: anyone on the LAN can watch panes and send keystrokes.
#   Revisit together with the Cloudflare tunnel (wss/TLS) follow-up.
# - User services die on logout unless `loginctl enable-linger sab` is set.
# - The hosted PWA (herdr-remote.pages.dev) can NOT be used on the LAN:
#   HTTPS pages are blocked from opening insecure ws:// connections.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.cli-apps.herdr-remote;
  herdrBin = "${inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr}/bin/herdr";
in
{
  options.custom.cli-apps.herdr-remote = {
    enable = mkBoolOpt false "Whether to enable the herdr-remote relay and web app services.";
    relayPort = mkOpt types.port 8375 "WebSocket port of the herdr-remote relay.";
    webPort = mkOpt types.port 8080 "HTTP port serving the herdr-remote web app.";
  };

  config = mkIf cfg.enable {
    systemd.user.services = {
      herdr-relay = {
        Unit = {
          Description = "herdr-remote relay (WebSocket bridge to herdr agents)";
        };
        Service = {
          ExecStart = getExe pkgs.custom.herdr-relay;
          Environment = [
            "HERDR_BIN=${herdrBin}"
            "HERDR_RELAY_PORT=${toString cfg.relayPort}"
          ];
          Restart = "on-failure";
        };
        # No Install.WantedBy on purpose: started manually via
        # `systemctl --user start herdr-relay`.
      };

      herdr-web = {
        Unit = {
          Description = "herdr-remote web app (static HTTP server)";
        };
        Service = {
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString cfg.webPort} --directory ${inputs.herdr-remote}/web";
          Restart = "on-failure";
        };
        # No Install.WantedBy on purpose: started manually via
        # `systemctl --user start herdr-web`.
      };
    };
  };
}
