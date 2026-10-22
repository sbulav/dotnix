# Route-only module (no container): serves the GStrummer guitar trainer
# (github.com/sbulav/gstrummer, private) from the host through Traefik.
#
# The app is a static build: `npm run deploy` in sab's gstrummer checkout
# builds it and rsyncs `dist/` into `dataPath`. Progress lives in each
# browser's IndexedDB, so the server holds no state.
#
# Its own socket-activated static-web-server instance: `services.static-web-server`
# is a single instance and gymup-report already owns it.
#
# Caching: `index.html`, `sw.js` and the manifests revalidate on every load so
# a new build is picked up; hashed `assets/*` never change. Deploys keep old
# assets (no --delete), so tabs and service workers on the previous build
# still find their chunks.
#
# Auth: Authelia (default auth-chain middleware) — the song catalog must not be
# published openly.
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
  cfg = config.${namespace}.containers.gstrummer;

  configFile = (pkgs.formats.toml { }).generate "gstrummer-sws.toml" {
    general = {
      log-level = "warn";
      directory-listing = false;
      # Headers below decide caching; SWS's per-extension defaults would make
      # index.html and sw.js stale for a day.
      cache-control-headers = false;
    };
    # Later entries override earlier ones for the same header.
    advanced.headers = [
      {
        source = "**";
        headers = {
          Cache-Control = "no-cache";
          X-Robots-Tag = "noindex, nofollow";
        };
      }
      {
        source = "/assets/**";
        headers.Cache-Control = "public, max-age=31536000, immutable";
      }
    ];
  };
in
{
  options.${namespace}.containers.gstrummer = with types; {
    enable = mkBoolOpt false "Enable the static GStrummer guitar trainer site.";
    host = mkOpt str "guitar.sbulav.ru" "The host to serve GStrummer on";
    dataPath = mkOpt str "/tank/gstrummer" "Directory the build is rsynced into (owned by sab)";
    listen = mkOpt str "127.0.0.1:8791" "Loopback address static-web-server listens on";
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

    systemd.sockets.gstrummer-web = {
      wantedBy = [ "sockets.target" ];
      listenStreams = [ cfg.listen ];
    };

    # Mirrors the sandboxing of the upstream static-web-server.service.
    systemd.services.gstrummer-web = {
      description = "GStrummer static site";
      requires = [ "gstrummer-web.socket" ];
      after = [ "gstrummer-web.socket" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.static-web-server}/bin/static-web-server --fd 0 --config-file ${configFile} --root ${cfg.dataPath}";
        # fd 0 is the listening socket even when started by multi-user.target,
        # not by a connection (`StandardInput = "socket"` would give it /dev/null).
        StandardInput = "fd:gstrummer-web.socket";
        StandardOutput = "journal";
        StandardError = "journal";
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        BindReadOnlyPaths = cfg.dataPath;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        CapabilityBoundingSet = "";
        RestrictNamespaces = true;
        RestrictAddressFamilies = "none";
        PrivateDevices = true;
        PrivateUsers = true;
        PrivateNetwork = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        RestrictRealtime = true;
        LockPersonality = true;
        RemoveIPC = true;
        MemoryDenyWriteExecute = true;
        UMask = "077";
        ProtectHostname = true;
        SystemCallFilter = "@system-service";
        DevicePolicy = "strict";
        DeviceAllow = [
          "/dev/null rw"
          "/dev/random r"
          "/dev/urandom r"
        ];
      };
    };

    custom.containers.traefik.routes = {
      gstrummer = {
        inherit (cfg) host;
        url = "http://${cfg.listen}";
        # No LAN bypass route: always behind Authelia.
        middlewares = [ "auth-chain" ];
      };
      # Chrome fetches the web manifest (and its icons) without cookies, so
      # behind Authelia the app could not be installed. They hold nothing
      # private.
      bypass-gstrummer = {
        service = "gstrummer";
        inherit (cfg) host;
        url = "http://${cfg.listen}";
        middlewares = [ "secure-headers" ];
        pathRegexp = "^/(manifest\\.webmanifest|icons/[a-z0-9-]+\\.png)$";
      };
    };
  };
}
