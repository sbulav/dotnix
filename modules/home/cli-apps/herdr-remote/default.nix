# herdr-remote: monitor and control herdr agents from a phone browser
# (https://github.com/sbulav/herdr-relay).
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
#   token (secrets/sab, key herdr_relay_token) on every connection. No longer
#   optional in practice — the relay exits at startup without a token, so this
#   flag only decides whether the wrapper hands it one. Authelia still guards
#   the Traefik path; the token is what keeps the LAN-direct ports from being
#   open. Retrieve it with:
#     sops -d --extract '["herdr_relay_token"]' secrets/sab/default.yaml
#   The web app takes the token in its own field and appends it as ?token=,
#   which is why it is not baked into defaultRelayUrl: that string is
#   substituted into an index.html served from a world-readable store path.
# - `hosts` is written to a world-readable store path. It carries SSH targets
#   and a wake MAC, which upstream keeps in a private config repo — but this
#   repo already held both as `remotes` and `powerHostMac`, so the exposure is
#   unchanged, not new. Nothing secret goes in here: a token or a key would
#   still have to come from sops.
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
  # Versioned host configuration (relay >= 0.8.0, protocol revision 3). It
  # replaced the flat preset allowlist: a client now picks a host, browses that
  # host's project roots for a folder, and chooses a harness and model from the
  # catalog the relay discovered. Schema: contract/host-config-v1.schema.json
  # in herdr-relay. Every key the relay does not know is rejected at startup,
  # so this mapping is deliberately literal.
  hostsFile = pkgs.writeText "herdr-hosts.json" (
    builtins.toJSON {
      schema_version = 1;
      hosts = map (
        host:
        {
          inherit (host) id;
          display_name = host.displayName;
          project_roots = host.projectRoots;
          herdr = {
            wrapper = host.herdrWrapper;
          }
          // optionalAttrs (host.herdrBinary != null) { binary = host.herdrBinary; };
          harnesses = map (harness: {
            inherit (harness) id;
            display_name = harness.displayName;
            inherit (harness) enabled;
            command = if harness.command == [ ] then [ harness.id ] else harness.command;
            model_aliases = map (alias: {
              inherit (alias) id;
              display_name = if alias.displayName == "" then alias.id else alias.displayName;
            }) harness.modelAliases;
          }) host.harnesses;
          power = {
            wake = if host.wakeMac == null then null else { mac = host.wakeMac; };
            inherit (host) shutdown;
          };
          readiness_timeout_seconds = host.readinessTimeoutSeconds;
        }
        // optionalAttrs (host.target != null) { ssh.target = host.target; }
      ) cfg.hosts;
    }
  );
  # HERDR_REMOTES is the relay's fallback topology and is read only when no
  # host file is configured. Passing both would suggest the two compose; they
  # do not, and the file wins.
  remotesEnv = optional (cfg.hosts == [ ]) "HERDR_REMOTES=${concatStringsSep "," cfg.remotes}";
  hostsEnv = optional (cfg.hosts != [ ]) "HERDR_HOSTS_FILE=${hostsFile}";
  # Saved-project metadata (relay >= 0.7.0, f73dd79) lives in a SQLite file the
  # relay creates on first use. The two relays are separate processes, so they
  # get separate databases rather than contending on one file. Discovered model
  # catalogs live in the same file, so each relay probes harnesses for itself.
  projectsDb = name: "${config.xdg.stateHome}/${name}/projects.sqlite3";
  webRoot = pkgs.runCommand "herdr-remote-web" { } ''
    cp -r ${inputs.herdr-remote}/web $out
    chmod -R u+w $out
    substituteInPlace $out/index.html \
      --replace-fail \
        "const autoRelayUrl = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host;" \
        "const autoRelayUrl = '${cfg.defaultRelayUrl}';"
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
    remotes =
      mkOpt (types.listOf types.str) [ ]
        "SSH hosts to poll when no `hosts` are configured. Ignored once `hosts` is non-empty.";
    hosts = mkOpt (types.listOf (
      types.submodule {
        options = {
          id = mkOpt types.str "" "Stable host identifier exposed to clients.";
          displayName = mkOpt types.str "" "Human-readable host name shown by clients.";
          target = mkOpt (types.nullOr types.str) null "SSH target, or null for the relay's own machine.";
          projectRoots =
            mkOpt (types.listOf types.str) [ ]
              "Absolute directories a client may browse for projects. A root is itself selectable.";
          herdrBinary =
            mkOpt (types.nullOr types.str) null
              "Absolute herdr path on this host, or null for HERDR_BIN.";
          herdrWrapper = mkOpt (types.listOf types.str) [ ] "Argv prefix placed before the herdr binary.";
          harnesses = mkOpt (types.listOf (
            types.submodule {
              options = {
                id = mkOpt types.str "" "Harness identifier. Also the executable the agent is started with.";
                displayName = mkOpt types.str "" "Human-readable harness name.";
                enabled = mkBoolOpt true "Whether the relay probes this harness at all.";
                command =
                  mkOpt (types.listOf types.str) [ ]
                    "Argv used to probe the harness, defaulting to its id.";
                modelAliases = mkOpt (types.listOf (
                  types.submodule {
                    options = {
                      id = mkOpt types.str "" "Model id passed to the harness as --model.";
                      displayName = mkOpt types.str "" "Human-readable model name, defaulting to the id.";
                    };
                  }
                )) [ ] "Models offered for a harness the relay cannot enumerate (Claude Code only).";
              };
            }
          )) [ ] "Coding agents installed on this host.";
          wakeMac =
            mkOpt (types.nullOr types.str) null
              "MAC to wake this host with, or null for no wake capability.";
          shutdown = mkBoolOpt false "Whether clients may shut this host down (requires an SSH target).";
          readinessTimeoutSeconds =
            mkOpt types.int 180
              "Ceiling on a single herdr call to this host, including the wait after a wake.";
        };
      }
    )) [ ] "Hosts the relay polls, browses, and launches agents on.";
    herdrBin = mkOpt types.str "herdr" "Herdr command to run locally and on SSH remotes.";
    defaultRelayUrl =
      mkOpt types.str "wss://herdr-relay.sbulav.ru"
        "Default WebSocket relay URL embedded in the web app.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = all (host: host.projectRoots != [ ]) cfg.hosts;
        message = "custom.cli-apps.herdr-remote.hosts: every host needs at least one project root, or the relay refuses to start.";
      }
      {
        assertion = all (host: !host.shutdown || host.target != null) cfg.hosts;
        message = "custom.cli-apps.herdr-remote.hosts: shutdown needs an SSH target — the relay runs poweroff over SSH.";
      }
    ];

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
            "HERDR_PROJECTS_DB=${projectsDb "herdr-relay"}"
            "PATH=${
              makeBinPath [
                herdrPackage
                pkgs.openssh
                pkgs.wakeonlan
              ]
            }"
          ]
          ++ remotesEnv
          ++ hostsEnv;
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
            "HERDR_PROJECTS_DB=${projectsDb "herdr-relay-mobile"}"
            "PATH=${
              makeBinPath [
                herdrPackage
                pkgs.openssh
                pkgs.wakeonlan
              ]
            }"
          ]
          ++ remotesEnv
          ++ hostsEnv;
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
