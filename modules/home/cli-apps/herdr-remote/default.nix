# herdr-remote: monitor and control herdr agents from a phone browser
# (https://github.com/dcolinmorgan/herdr-remote).
#
# Browser services plus an optional token-authenticated mobile relay:
#   systemctl --user start herdr-relay   # WebSocket relay on :8375
#   systemctl --user start herdr-web     # static web app on :8080
#   systemctl --user start herdr-relay-mobile # native app relay on :8377
# Phone on LAN: open http://<host>:8080, enter ws://<host>:8375 as relay URL.
# Remote: served via Traefik on zanoza as herdr.sbulav.ru / herdr-relay.sbulav.ru
# behind Authelia (see modules/nixos/containers/herdr-remote).
#
# Notes / accepted risks:
# - Token auth (enableTokenAuth): the relay requires the sops-managed shared
#   token (secrets/sab, key herdr_relay_token) on every connection. Disabled
#   on zanoza — Authelia guards the Traefik path instead; the LAN-direct ports
#   are accepted as open. Retrieve the token (if re-enabled) with:
#     sops -d --extract '["herdr_relay_token"]' secrets/sab/default.yaml
# - Without autoStart, user services die on logout unless linger is enabled.
# - The hosted PWA (herdr-remote.pages.dev) can NOT be used: on the LAN,
#   HTTPS pages are blocked from opening insecure ws:// connections; via
#   Traefik, Authelia's cookie is not sent cross-site. Use the self-hosted app.
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
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
  mobilePresets = pkgs.writeText "herdr-mobile-presets.json" (
    builtins.toJSON {
      schema_version = 1;
      inherit (cfg) presets;
    }
  );
  webRoot = pkgs.runCommand "herdr-remote-web" { } ''
    cp -r ${inputs.herdr-remote}/web $out
    chmod -R u+w $out
    substituteInPlace $out/index.html \
      --replace-fail \
        "const DEFAULT_RELAY = 'wss://your-relay.example.com';" \
        "const DEFAULT_RELAY = '${cfg.defaultRelayUrl}';" \
      --replace-fail \
        "const DEFAULT_TOKEN = 'YOUR_TOKEN_HERE';" \
        "const DEFAULT_TOKEN = String();" \
      --replace-fail \
        "let url = localStorage.getItem('herdr_relay_url');" \
        "let url = localStorage.getItem('herdr_relay_url') || DEFAULT_RELAY;"
  '';
in
{
  options.custom.cli-apps.herdr-remote = {
    enable = mkBoolOpt false "Whether to enable the herdr-remote relay and web app services.";
    relayPort = mkOpt types.port 8375 "WebSocket port of the herdr-remote relay.";
    mobileRelayPort =
      mkOpt types.port 8377
        "WebSocket port of the token-authenticated native mobile relay.";
    webPort = mkOpt types.port 8080 "HTTP port serving the herdr-remote web app.";
    enableTokenAuth = mkBoolOpt true "Whether to require a shared token (from sops) for relay connections.";
    enableMobileRelay = mkBoolOpt false "Whether to run a separate token-authenticated relay for the native Android app.";
    autoStart = mkBoolOpt false "Whether to start the relay and web app services automatically (requires linger to survive logout).";
    remotes = mkOpt (types.listOf types.str) [ ] "SSH hosts to poll for remote herdr instances.";
    presets = mkOpt (types.listOf (
      types.submodule {
        options = {
          id = mkOpt types.str "" "Stable preset identifier exposed to native clients.";
          label = mkOpt types.str "" "Human-readable preset label.";
          repository = mkOpt types.str "" "Stable repository identifier shown by native clients.";
          agent = mkOpt (types.enum [
            "claude"
            "opencode"
            "codex"
          ]) "claude" "Agent executable selected by the relay.";
          model = mkOpt types.str "default" "Model passed through the relay's fixed agent template.";
          hosts = mkOpt (types.attrsOf (
            types.submodule {
              options = {
                cwd = mkOpt types.str "" "Absolute working directory on this host.";
                target = mkOpt (types.nullOr types.str) null "SSH target, or null for the relay host.";
              };
            }
          )) { } "Allowed launch hosts and their server-owned paths.";
        };
      }
    )) [ ] "Server-owned presets available to native mobile clients.";
    herdrBin = mkOpt types.str "herdr" "Herdr command to run locally and on SSH remotes.";
    powerHostId = mkOpt types.str "" "Single host allowed for native mobile power controls.";
    powerHostMac = mkOpt types.str "" "MAC address used to wake the allowed power host.";
    defaultRelayUrl =
      mkOpt types.str "wss://herdr-relay.sbulav.ru"
        "Default WebSocket relay URL embedded in the web app.";
  };

  config = mkIf cfg.enable {
    sops.secrets.herdr_relay_token = mkIf (cfg.enableTokenAuth || cfg.enableMobileRelay) {
      sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
    };

    systemd.user.services = {
      herdr-relay = {
        Unit = {
          Description = "herdr-remote relay (WebSocket bridge to herdr agents)";
        };
        Service = {
          # Wrapper reads the token at runtime so it never lands in the nix
          # store or in `systemctl show` output.
          ExecStart = pkgs.writeShellScript "herdr-relay-start" ''
            ${optionalString cfg.enableTokenAuth ''
              export HERDR_RELAY_TOKEN="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.herdr_relay_token.path})"
            ''}
            exec ${getExe pkgs.custom.herdr-relay}
          '';
          Environment = [
            "HERDR_BIN=${cfg.herdrBin}"
            "HERDR_RELAY_PORT=${toString cfg.relayPort}"
            "HERDR_REMOTES=${concatStringsSep "," cfg.remotes}"
            "PATH=${
              makeBinPath [
                herdrPackage
                pkgs.openssh
              ]
            }"
          ];
          Restart = "on-failure";
        };
        Install = mkIf cfg.autoStart {
          WantedBy = [ "default.target" ];
        };
      };

      herdr-relay-mobile = mkIf cfg.enableMobileRelay {
        Unit = {
          Description = "herdr-remote native mobile relay (token-authenticated WebSocket bridge)";
        };
        Service = {
          ExecStart = pkgs.writeShellScript "herdr-relay-mobile-start" ''
            export HERDR_RELAY_TOKEN="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.herdr_relay_token.path})"
            exec ${getExe pkgs.custom.herdr-relay}
          '';
          Environment = [
            "HERDR_BIN=${cfg.herdrBin}"
            "HERDR_RELAY_PORT=${toString cfg.mobileRelayPort}"
            "HERDR_REMOTES=${concatStringsSep "," cfg.remotes}"
            "HERDR_PRESETS_FILE=${mobilePresets}"
            "HERDR_POWER_HOST_ID=${cfg.powerHostId}"
            "HERDR_POWER_HOST_MAC=${cfg.powerHostMac}"
            "PATH=${
              makeBinPath [
                herdrPackage
                pkgs.openssh
                pkgs.wakeonlan
              ]
            }"
          ];
          Restart = "on-failure";
        };
        Install = mkIf cfg.autoStart {
          WantedBy = [ "default.target" ];
        };
      };

      herdr-web = {
        Unit = {
          Description = "herdr-remote web app (static HTTP server)";
        };
        Service = {
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString cfg.webPort} --directory ${webRoot}";
          Restart = "on-failure";
        };
        Install = mkIf cfg.autoStart {
          WantedBy = [ "default.target" ];
        };
      };
    };
  };
}
