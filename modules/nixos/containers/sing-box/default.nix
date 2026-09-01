# sing-box proxy container: VLESS+REALITY exits with automatic failover.
# Replaces the former v2rayA container (and the host-level tv-proxy-router):
# a urltest group probes every exit and routes around blocked ones; a
# selector ("exit", default "auto") lets the metacubexd dashboard pin one.
# RU-destined traffic goes direct; everything else through the selector.
# Consumers of the SOCKS endpoint 172.16.64.108:20170 (arr apps, beez
# telegram via host port-forward, redsocks TV chain) are unchanged.
{
  pkgs,
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.sing-box;

  # Parses the sops-provided vless:// URI list into sing-box outbounds plus
  # the urltest/selector groups. Runs as a root ExecStartPre inside the
  # container (secrets are 0400); output tags come from the URI fragments,
  # so adding/removing an exit is a sops edit only — no Nix change.
  outboundsGen = pkgs.writers.writePython3Bin "sing-box-outbounds-gen" { } ''
    import json
    import os
    import sys
    from urllib.parse import parse_qs, unquote, urlsplit

    uris_file, out_file = sys.argv[1], sys.argv[2]

    outbounds = []
    with open(uris_file) as f:
        for line in f:
            uri = line.strip()
            if not uri:
                continue
            if not uri.startswith("vless://"):
                print(f"skipping non-vless line: {uri[:16]}...",
                      file=sys.stderr)
                continue
            u = urlsplit(uri)
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            if q.get("security") != "reality":
                print(f"skipping non-reality server {u.hostname}",
                      file=sys.stderr)
                continue
            tag = unquote(u.fragment) or u.hostname
            outbound = {
                "type": "vless",
                "tag": tag,
                "server": u.hostname,
                "server_port": u.port or 443,
                "uuid": u.username,
                "tls": {
                    "enabled": True,
                    "server_name": q.get("sni", ""),
                    "utls": {
                        "enabled": True,
                        "fingerprint": q.get("fp", "chrome"),
                    },
                    "reality": {
                        "enabled": True,
                        "public_key": q.get("pbk", ""),
                        "short_id": q.get("sid", ""),
                    },
                },
            }
            if q.get("flow"):
                outbound["flow"] = q["flow"]
            outbounds.append(outbound)

    if not outbounds:
        sys.exit("no valid vless URIs parsed — refusing to start "
                 "with a direct-only config")

    tags = [o["tag"] for o in outbounds]
    outbounds.append({
        "type": "urltest",
        "tag": "auto",
        "outbounds": tags,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "1m",
        "tolerance": 50,
    })
    outbounds.append({
        "type": "selector",
        "tag": "exit",
        "outbounds": ["auto"] + tags,
        "default": "auto",
    })

    tmp = out_file + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"outbounds": outbounds}, f)
    # Match the runtime dir's owner (the sing-box user) so the service
    # can read the file — same trick the nixpkgs module uses for its
    # rendered config.json.
    st = os.stat(os.path.dirname(out_file))
    os.chown(tmp, st.st_uid, st.st_gid)
    os.rename(tmp, out_file)
    print(f"generated {len(tags)} exits: {', '.join(tags)}")
  '';
in
{
  options.${namespace}.containers.sing-box = with types; {
    enable = mkBoolOpt false "Enable sing-box nixos-container;";
    dataPath = mkOpt str "/tank/sing-box" "sing-box data path on host machine";
    host = mkOpt str "sing-box.sbulav.ru" "The host to serve the clash dashboard on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.108" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret file for sing-box credentials";
  };
  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "sing-box";
      host = cfg.host;
      url = "http://${cfg.localAddress}:9090";
      route_enabled = cfg.enable;
      middleware = [
        "secure-headers"
        "allow-lan"
      ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    # Secrets are decrypted on the host and bind-mounted into the container.
    # restartUnits: a changed secret must restart the container so the
    # outbounds are regenerated; fires only on content change.
    custom.security.sops.secrets = {
      "sing-box/admin_password" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        mode = "0400";
        restartUnits = [ "container@sing-box.service" ];
      };
      "sing-box/vless_uris" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        mode = "0400";
        restartUnits = [ "container@sing-box.service" ];
      };
    };

    # Pre-existing host NAT for privateNetwork container egress (unchanged).
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-sing-box" ];
      externalInterface = "enp3s0";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataPath}/logs 0755 root root -"
      "d ${cfg.dataPath}/state 0755 root root -"
    ];

    containers.sing-box = {
      ephemeral = true;
      autoStart = true;

      bindMounts = {
        "/var/log/sing-box" = {
          hostPath = "${cfg.dataPath}/logs";
          isReadOnly = false;
        };
        # cache.db lives here: selector pin + urltest history survive
        # restarts of the ephemeral container.
        "/var/lib/sing-box" = {
          hostPath = "${cfg.dataPath}/state";
          isReadOnly = false;
        };
        "${config.sops.secrets."sing-box/admin_password".path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets."sing-box/vless_uris".path}" = {
          isReadOnly = true;
        };
      };
      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      # 20170 must stay reachable at the host's LAN IP: beez uses
      # socks5h://192.168.89.207:20170 (former v2rayA ports 20171/20172
      # had no consumers and are dropped).
      forwardPorts = [
        {
          containerPort = 20170;
          hostPort = 20170;
          protocol = "tcp";
        }
      ];
      config =
        { ... }:
        {
          services.sing-box = {
            enable = true;
            settings = {
              log = {
                level = "info";
                output = "/var/log/sing-box/sing-box.log";
                timestamp = true;
              };
              dns.servers = [
                {
                  type = "udp";
                  tag = "adguard";
                  server = "172.16.64.104";
                }
              ];
              inbounds = [
                {
                  # SOCKS5 + HTTP on the former v2rayA SOCKS port
                  type = "mixed";
                  tag = "in";
                  listen = "0.0.0.0";
                  listen_port = 20170;
                }
              ];
              # vless outbounds + "auto" urltest + "exit" selector are
              # generated into /run/sing-box/10-outbounds.json from sops;
              # sing-box -C merges every *.json in the directory.
              outbounds = [
                {
                  type = "direct";
                  tag = "direct";
                }
              ];
              route = {
                default_domain_resolver = "adguard";
                rule_set = [
                  {
                    type = "local";
                    format = "binary";
                    tag = "geosite-category-ru";
                    path = "${pkgs.sing-geosite}/share/sing-box/rule-set/geosite-category-ru.srs";
                  }
                  {
                    type = "local";
                    format = "binary";
                    tag = "geoip-ru";
                    path = "${pkgs.sing-geoip}/share/sing-box/rule-set/geoip-ru.srs";
                  }
                ];
                rules = [
                  # redsocks hands us bare IPs; sniff recovers SNI/Host so
                  # the domain rules below can catch RU sites before the
                  # geoip fallback.
                  { action = "sniff"; }
                  {
                    domain_suffix = [
                      "sbulav.ru"
                      "pyn.ru"
                      "hhdev.ru"
                    ];
                    rule_set = [ "geosite-category-ru" ];
                    domain_regex = [
                      "\\.ru$"
                      "\\.su$"
                      "\\.xn--p1ai$"
                    ];
                    outbound = "direct";
                  }
                  {
                    ip_is_private = true;
                    outbound = "direct";
                  }
                  {
                    rule_set = [ "geoip-ru" ];
                    outbound = "direct";
                  }
                ];
                final = "exit";
              };
              experimental = {
                clash_api = {
                  external_controller = "0.0.0.0:9090";
                  external_ui = "${pkgs.metacubexd}";
                  secret._secret = config.sops.secrets."sing-box/admin_password".path;
                };
                cache_file.enabled = true;
              };
            };
          };

          # "+" = run as root: the sops secret is 0400 and the module's own
          # ExecStartPre (config.json render) also runs privileged.
          systemd.services.sing-box.serviceConfig.ExecStartPre = mkAfter [
            "+${outboundsGen}/bin/sing-box-outbounds-gen ${
              config.sops.secrets."sing-box/vless_uris".path
            } /run/sing-box/10-outbounds.json"
          ];

          # Bind mounts arrive root-owned; hand them to the service user.
          systemd.tmpfiles.rules = [
            "Z /var/log/sing-box - sing-box sing-box -"
            "Z /var/lib/sing-box - sing-box sing-box -"
          ];

          networking = {
            enableIPv6 = false;
            firewall.enable = false;
            # Use systemd-resolved inside the container
            # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
            useHostResolvConf = lib.mkForce false;
          };
          services.resolved = {
            enable = true;
            settings.Resolve.DNS = "172.16.64.104";
          };
          system.stateVersion = "26.05";
        };
    };
  };
}
