# sing-box proxy container: VLESS exits (REALITY over TCP, or TLS over
# gRPC) with automatic failover.
# Replaces the former v2rayA container (and the host-level tv-proxy-router):
# a urltest group probes every exit and routes around blocked ones; a
# selector ("exit", default "auto") lets the metacubexd dashboard pin one.
# RU-destined traffic goes direct; everything else through the selector.
# Consumers of the SOCKS endpoint 172.16.64.108:20170 (arr apps, beez
# telegram via host port-forward, redsocks TV chain) are unchanged.
#
# The exits come from the provider's Happ subscription (URL in sops): a
# host-side timer refreshes them every cfg.subscription.interval, validates
# the result and restarts the container only when the server list actually
# changed. Upstream sing-box has no subscription support of its own, so
# the conversion lives here. A failed refresh keeps the last good list and
# is reported once per cfg.notify.throttle through Telegram/email.
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
  householdDnsSettings = lib.custom.dns.resolvedSettings;
  cfg = config.${namespace}.containers.sing-box;

  hostName = config.networking.hostName;

  # The exits live on the host at ${cfg.dataPath}/state/outbounds.json and
  # reach the container through the existing /var/lib/sing-box bind mount.
  outboundsFile = "${cfg.dataPath}/state/outbounds.json";
  containerOutboundsFile = "/var/lib/sing-box/outbounds.json";
  failureStamp = "${cfg.dataPath}/state/.subscription-failure-notified";

  # Converts the Happ subscription (a JSON list of complete Xray profiles,
  # one per location plus an aggregate "auto" profile) into sing-box
  # outbounds plus the urltest/selector groups. Only REALITY/TCP and
  # TLS/gRPC are mapped; anything else is skipped with a message. Tags are
  # derived from the profile name ("🇩🇪 AliceVPN Германия" ->
  # "AliceVPN-DE-vless") so a selector pin in cache.db survives the
  # provider rotating a server's IP.
  outboundsGen = pkgs.writers.writePython3Bin "sing-box-outbounds-gen" { } ''
    import json
    import os
    import sys

    sub_file, out_file = sys.argv[1], sys.argv[2]
    urltest_interval, urltest_tolerance = sys.argv[3], int(sys.argv[4])

    # Tags already claimed by the static config / the groups below; a
    # colliding or duplicate tag makes sing-box reject the merged config.
    RESERVED_TAGS = {"auto", "exit", "direct"}

    with open(sub_file) as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        sys.exit("subscription is neither a profile list nor a profile")


    def flag_to_cc(text):
        """'🇩🇪 AliceVPN Германия' -> ('DE', 'AliceVPN Германия')."""
        letters = []
        rest = []
        for ch in text:
            cp = ord(ch)
            if 0x1F1E6 <= cp <= 0x1F1FF and not rest:
                letters.append(chr(cp - 0x1F1E6 + ord("A")))
            else:
                rest.append(ch)
        cc = "".join(letters) if len(letters) == 2 else ""
        return cc, "".join(rest).strip()


    def make_tag(remarks, server):
        cc, rest = flag_to_cc(remarks or "")
        name = rest.split()[0] if rest else ""
        if cc and name:
            return f"{name}-{cc}-vless"
        return rest or server


    def convert(xo, tag):
        """One xray vless outbound -> sing-box outbound, or None."""
        vnext = (xo.get("settings") or {}).get("vnext") or []
        if len(vnext) != 1 or not (vnext[0].get("users") or []):
            print(f"skipping {tag}: expected exactly one vnext/user",
                  file=sys.stderr)
            return None
        srv, user = vnext[0], vnext[0]["users"][0]
        if user.get("encryption", "none") != "none":
            print(f"skipping {tag}: vless encryption must be 'none'",
                  file=sys.stderr)
            return None
        ss = xo.get("streamSettings") or {}
        transport = ss.get("network") or "tcp"
        security = ss.get("security")
        if transport not in ("tcp", "grpc"):
            print(f"skipping {tag}: unsupported transport {transport!r}",
                  file=sys.stderr)
            return None
        if security not in ("reality", "tls"):
            print(f"skipping {tag}: unsupported security {security!r}",
                  file=sys.stderr)
            return None
        is_grpc = transport == "grpc"
        if is_grpc:
            g = ss.get("grpcSettings") or {}
            # sing-box speaks only gun-mode gRPC; there is no "multi".
            if g.get("multiMode"):
                print(f"skipping {tag}: multi-mode gRPC is unsupported",
                      file=sys.stderr)
                return None
        # An accepted server must be complete: an empty key/SNI renders
        # an invalid config, and sing-box check below would reject it.
        if security == "reality":
            rs = ss.get("realitySettings") or {}
            if not rs.get("publicKey") or not rs.get("serverName"):
                sys.exit(f"{tag}: reality without publicKey/serverName")
            tls = {
                "enabled": True,
                "server_name": rs["serverName"],
                "utls": {
                    "enabled": True,
                    "fingerprint": rs.get("fingerprint") or "chrome",
                },
                "reality": {
                    "enabled": True,
                    "public_key": rs["publicKey"],
                    "short_id": rs.get("shortId") or "",
                },
            }
        else:
            ts = ss.get("tlsSettings") or {}
            if not ts.get("serverName"):
                sys.exit(f"{tag}: tls without serverName")
            tls = {
                "enabled": True,
                "server_name": ts["serverName"],
                "utls": {
                    "enabled": True,
                    "fingerprint": ts.get("fingerprint") or "chrome",
                },
            }
            if ts.get("alpn"):
                tls["alpn"] = list(ts["alpn"])
        out = {
            "type": "vless",
            "tag": tag,
            "server": srv["address"],
            "server_port": int(srv.get("port") or 443),
            "uuid": user["id"],
            "tls": tls,
        }
        if is_grpc:
            out["transport"] = {
                "type": "grpc",
                "service_name": g.get("serviceName", ""),
            }
        # Vision is TCP-only; never carry flow onto a gRPC outbound.
        elif user.get("flow"):
            out["flow"] = user["flow"]
        return out


    # Per-location profiles carry the readable name, so they win; the
    # aggregate profile is only a fallback for a provider that ships
    # nothing else (its servers are then tagged by address).
    single, aggregate = [], []
    for p in data:
        vless = [o for o in p.get("outbounds") or []
                 if o.get("protocol") == "vless"]
        if not vless:
            continue
        bucket = single if len(vless) == 1 else aggregate
        bucket.append((p.get("remarks", ""), vless))

    outbounds, seen_tags, seen_servers = [], set(), set()
    for remarks, vless in (single or aggregate):
        for xo in vless:
            vnext = (xo.get("settings") or {}).get("vnext") or [{}]
            server = vnext[0].get("address", "?")
            tag = make_tag(remarks, server) if len(vless) == 1 else server
            out = convert(xo, tag)
            if out is None:
                continue
            key = (out["server"], out["server_port"], out["uuid"])
            if key in seen_servers:
                continue
            if tag in RESERVED_TAGS:
                sys.exit(f"tag {tag!r} collides with a built-in tag")
            if tag in seen_tags:
                sys.exit(f"duplicate outbound tag {tag!r}")
            seen_tags.add(tag)
            seen_servers.add(key)
            outbounds.append(out)

    if not outbounds:
        sys.exit("no usable vless outbounds in the subscription — "
                 "refusing to publish a direct-only config")

    tags = [o["tag"] for o in outbounds]
    outbounds.append({
        "type": "urltest",
        "tag": "auto",
        "outbounds": tags,
        "url": "https://www.gstatic.com/generate_204",
        "interval": urltest_interval,
        "tolerance": urltest_tolerance,
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
        json.dump({"outbounds": outbounds}, f, indent=1, sort_keys=True)
        f.write("\n")
    os.rename(tmp, out_file)
    print(f"generated {len(tags)} exits: {', '.join(tags)}")
  '';

  # Host-side refresh: fetch the subscription, convert, validate with
  # `sing-box check`, and publish atomically only when the exits changed —
  # a restart of the container is the one visible side effect. A failed
  # fetch exits non-zero (so OnFailure= reports it) but leaves the last
  # good file in place; the container keeps running from it.
  #
  # The provider's own host is DPI-blocked on zanoza's uplink (TCP opens,
  # the TLS handshake never completes), so the fetch goes through the
  # proxy itself first and falls back to direct — the fallback is what a
  # fresh host with no exits yet, or a different uplink, relies on.
  subscriptionUpdate = pkgs.writeShellApplication {
    name = "sing-box-subscription-update";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      diffutils
      gawk
      gnugrep
      sing-box
      systemd
      outboundsGen
    ];
    text = ''
      url=$(tr -d '[:space:]' < ${config.sops.secrets."sing-box/subscription_url".path})
      state=${outboundsFile}
      work=$(mktemp -d)
      # shellcheck disable=SC2329
      cleanup() { rm -rf "$work"; }
      trap cleanup EXIT

      fetch() {
        curl -fsS --connect-timeout 10 --max-time 60 \
          -A ${escapeShellArg cfg.subscription.userAgent} \
          -D "$work/headers" -o "$work/sub.json" "$@" "$url"
      }
      proxy=${escapeShellArg cfg.subscription.proxyUrl}
      if [ -n "$proxy" ] && fetch --proxy "$proxy"; then
        echo "fetched via $proxy"
      elif fetch; then
        echo "fetched directly"
      else
        echo "subscription fetch failed (proxy and direct)" >&2
        [ -s "$state" ] && echo "keeping the last good exits in $state" >&2
        exit 1
      fi

      # subscription-userinfo: upload=..; download=..; total=..; expire=<unix>
      info=$(tr -d '\r' < "$work/headers" | grep -i '^subscription-userinfo:' || true)
      if [ -n "$info" ]; then
        echo "$info" | awk -F'[;:= ]+' '{
          for (i = 1; i <= NF; i++) v[$i] = $(i + 1)
          printf "subscription: %.1f of %.0f GiB used, expires %s\n",
            (v["upload"] + v["download"]) / 2^30, v["total"] / 2^30,
            strftime("%Y-%m-%d", v["expire"])
        }'
      fi

      sing-box-outbounds-gen "$work/sub.json" "$work/outbounds.json" \
        ${escapeShellArg cfg.urltest.interval} ${toString cfg.urltest.tolerance}
      sing-box check -c "$work/outbounds.json"

      if cmp -s "$work/outbounds.json" "$state"; then
        echo "exits unchanged"
      else
        mkdir -p "$(dirname "$state")"
        install -m 0644 "$work/outbounds.json" "$state.tmp"
        mv -f "$state.tmp" "$state"
        echo "published new exits to $state"
        # --no-block: the container is ordered After= this unit, so a
        # blocking restart from inside it would wait on itself.
        if systemctl is-active --quiet container@sing-box.service; then
          systemctl --no-block restart container@sing-box.service
        fi
      fi
      # A good run re-arms the failure notification.
      rm -f ${failureStamp}
    '';
  };

  # Installs the published exits into the container's runtime dir with the
  # owner of that dir (the sing-box user) — same trick the nixpkgs module
  # uses for its rendered config.json.
  outboundsInstall = pkgs.writeShellApplication {
    name = "sing-box-outbounds-install";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      src=$1
      dst=$2
      if ! [ -s "$src" ]; then
        echo "no exits at $src: the host's sing-box-subscription.service" \
             "has not published any yet (check its journal)" >&2
        exit 1
      fi
      cp "$src" "$dst.tmp"
      chown --reference="$(dirname "$dst")" "$dst.tmp"
      chmod 0600 "$dst.tmp"
      mv -f "$dst.tmp" "$dst"
    '';
  };

  # --- Notifications -------------------------------------------------------
  notifyEnabled = cfg.notify.telegram.enable || cfg.notify.email.enable;
  deliverScript = lib.${namespace}.notifications.mkDeliverScript pkgs {
    inherit hostName;
    telegram = {
      inherit (cfg.notify.telegram) enable chatId proxyUrl;
    };
    email = {
      inherit (cfg.notify.email) enable recipient;
      fromName = "${hostName} sing-box";
    };
  };
  # Only referenced from `mkIf notifyEnabled` blocks: with both channels
  # disabled mkDeliverScript refuses to build, and it must not be forced.
  deliver = "${deliverScript}/bin/notify-deliver";

  # The provider being down for hours would otherwise page once an hour;
  # the stamp throttles to one message per cfg.notify.throttle, and a
  # successful refresh clears it.
  subscriptionFailure = pkgs.writeShellApplication {
    name = "sing-box-subscription-notify-failure";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      unit=sing-box-subscription.service
      stamp=${failureStamp}
      now=$(date +%s)
      if [ -f "$stamp" ] && [ $(( now - $(cat "$stamp") )) -lt ${toString cfg.notify.throttle} ]; then
        echo "failure already reported within the throttle window"
        exit 0
      fi
      message_file=$(mktemp)
      # shellcheck disable=SC2329
      cleanup() { rm -f "$message_file"; }
      trap cleanup EXIT
      result=$(systemctl show -p Result --value "$unit")
      invocation=$(systemctl show -p InvocationID --value "$unit")
      {
        printf '%s\n' "🔥 ${hostName} | sing-box subscription refresh failed"
        printf 'Unit: %s\nResult: %s\n\n' "$unit" "$result"
        printf 'Last 10 journal lines:\n'
        if [ -n "$invocation" ]; then
          journalctl _SYSTEMD_INVOCATION_ID="$invocation" -n 10 -o cat --no-pager || true
        else
          journalctl -u "$unit" -n 10 -o cat --no-pager || true
        fi
        printf '\nThe proxy keeps running from the last good exits in %s.\n' ${outboundsFile}
        printf 'Inspect: journalctl -u %s\n' "$unit"
      } >"$message_file"
      ${deliver} "$message_file" "[${hostName}] sing-box subscription failed" high
      echo "$now" >"$stamp"
    '';
  };

  # metacubexd with the backend pre-filled via its config.js hook. The
  # dashboard is reached through traefik on ${cfg.host}, so the clash API
  # shares that HTTPS origin; the stock default (http://127.0.0.1:9090)
  # is unreachable there and trips the browser's mixed-content block.
  # Only the API secret is left for the user to paste (it lives in sops,
  # not the store); metacubexd persists it in localStorage afterwards.
  metacubexd = pkgs.runCommand "metacubexd-configured" { } ''
    cp -r ${pkgs.metacubexd} $out
    chmod +w $out $out/config.js
    echo "window.__METACUBEXD_CONFIG__ = { defaultBackendURL: 'https://${cfg.host}' }" \
      > $out/config.js
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

    subscription = {
      interval =
        mkOpt str "1h"
          "How often to refresh the exits from the subscription (systemd time span; the provider advertises profile-update-interval: 1)";
      userAgent =
        mkOpt str "Happ"
          "User-Agent for the subscription fetch (some providers vary the format by client)";
      proxyUrl =
        mkOpt str "socks5h://${cfg.localAddress}:20170"
          "curl proxy tried first for the subscription fetch (the provider's host is DPI-blocked on the uplink); direct is the fallback. Empty disables";
    };

    # Second inbound for the redsocks transparent-proxy chain (TVs, home
    # phones): the routers forward *every* Google-service connection here
    # because an IP list cannot tell www.google.com from www.youtube.com
    # (shared front ends). sing-box can: it sniffs the SNI/Host and sends
    # only the DPI-blocked YouTube names to the exit, the rest direct.
    # Android's connectivity checks (connectivitycheck.gstatic.com,
    # www.google.com/generate_204) and push (mtalk) thus no longer ride
    # the VLESS tunnel, which is what made phones drop Wi-Fi when an exit
    # flapped. The main inbound (20170) keeps the old everything-via-exit
    # behaviour for the arr apps and Telegram.
    transparent = {
      port = mkOpt port 20171 "SOCKS5 port for the transparent-proxy chain (redsocks upstream)";
      proxyDomains =
        mkOpt (listOf str)
          [
            "youtube.com"
            "youtube-nocookie.com"
            "youtu.be"
            "googlevideo.com"
            "ytimg.com"
            "ggpht.com"
            "youtubei.googleapis.com"
            "youtube.googleapis.com"
            "youtubeembeddedplayer.googleapis.com"
            "play.google.com"
          ]
          "Domain suffixes from the transparent inbound that go to the exit; everything else sniffed there goes direct. Measured as DPI-blocked from beez on 2026-10-16";
    };

    # urltest churn: every switch of the carrying exit changes the egress
    # IP, and googlevideo answers that with 403s mid-stream. Probe less
    # often and only move for a clearly better exit.
    urltest = {
      interval = mkOpt str "3m" "urltest probe interval for the auto group";
      tolerance = mkOpt int 150 "urltest tolerance in ms: a better exit must win by at least this much";
    };

    # Notifications for a failing refresh: Telegram first, email through
    # msmtp when Telegram fails (same deliverer as restic).
    notify = {
      throttle =
        mkOpt int 21600
          "Seconds between repeated failure notifications while the refresh keeps failing; a successful refresh re-arms it";
      telegram = {
        enable = mkBoolOpt true "Report a failing subscription refresh to Telegram";
        chatId = mkOpt str "681806836" "Telegram chat ID for notifications";
        proxyUrl =
          mkOpt str ""
            "Optional curl proxy URL for api.telegram.org (zanoza reaches it only through the sing-box SOCKS proxy)";
      };
      email = {
        enable = mkBoolOpt false "Fall back to email (custom.containers.msmtp) when Telegram delivery fails";
        recipient = mkOpt str "" "Fallback notification recipient";
      };
    };
  };
  imports = [
    (import ../shared/shared-adguard-dns-rewrite.nix {
      inherit (cfg) host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.notify.email.enable || config.${namespace}.containers.msmtp.enable;
        message = "custom.containers.sing-box.notify.email.enable requires custom.containers.msmtp.enable";
      }
      {
        assertion = !cfg.notify.email.enable || cfg.notify.email.recipient != "";
        message = "custom.containers.sing-box.notify.email.recipient must be set when email notifications are enabled";
      }
    ];

    custom.containers.traefik = {
      # This module defines sing-box-ui-redirect below; register it so routes
      # may name it.
      knownMiddlewares = [ "sing-box-ui-redirect" ];

      routes.sing-box = {
        inherit (cfg) host;
        url = "http://${cfg.localAddress}:9090";
        # auth-chain (= secure-headers + authelia) keeps the dashboard SSO-gated
        # like every other admin UI; allow-lan additionally pins it to LAN
        # sources. The clash API secret alone is not enough — the dashboard can
        # pin/unpin exits.
        middlewares = [
          "auth-chain"
          "allow-lan"
          # The clash API root answers 401 to anything without the bearer
          # secret; metacubexd is served under /ui/. Defined below, next to
          # the traefik container gate.
          "sing-box-ui-redirect"
        ];
      };
    };

    # Secrets are decrypted on the host. The admin password is bind-mounted
    # into the container; the subscription URL stays host-only (the refresh
    # unit reads it) and a changed URL re-runs that unit, which in turn
    # restarts the container if the exits differ.
    custom.security.sops.secrets = {
      "sing-box/admin_password" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        mode = "0400";
        restartUnits = [ "container@sing-box.service" ];
      };
      "sing-box/subscription_url" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        mode = "0400";
        restartUnits = [ "sing-box-subscription.service" ];
      };
      # Shared telegram bot token for notifications (UID 1000 for user
      # services); restic declares the same secret on zanoza, the attrs merge.
      "telegram-notifications-bot-token" = mkIf cfg.notify.telegram.enable (
        lib.custom.secrets.services.sharedTelegramBot 1000
        // {
          sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        }
      );
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

    # tmpfiles alone is not enough on first activation: during a switch the
    # tmpfiles pass and the container start land in the same transaction with
    # no ordering, and nspawn hard-fails on a missing bind-mount *source*
    # (it only auto-creates missing targets). Same pattern as opencloud's
    # posix-storage-prepare oneshot.
    systemd.services.sing-box-data-prepare = {
      description = "Ensure sing-box data directories exist";
      wantedBy = [ "container@sing-box.service" ];
      before = [ "container@sing-box.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${cfg.dataPath}/logs ${cfg.dataPath}/state";
      };
    };

    # Subscription refresh. Ordered before the container so a fresh host
    # (or a host that lost ${cfg.dataPath}) has exits before sing-box
    # starts; Wants= (not Requires=) so a provider outage never takes the
    # proxy down — the container then starts from the last published file.
    systemd.services.sing-box-subscription = {
      description = "Refresh sing-box exits from the VPN subscription";
      after = [
        "network-online.target"
        "sing-box-data-prepare.service"
        "sops-nix.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "sing-box-data-prepare.service" ];
      before = [ "container@sing-box.service" ];
      wantedBy = [ "container@sing-box.service" ];
      onFailure = mkIf notifyEnabled [ "sing-box-subscription-failure.service" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "5min";
        ExecStart = "${subscriptionUpdate}/bin/sing-box-subscription-update";
      };
    };
    systemd.timers.sing-box-subscription = {
      description = "Periodic sing-box subscription refresh";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.subscription.interval;
        OnUnitActiveSec = cfg.subscription.interval;
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
    systemd.services.sing-box-subscription-failure = mkIf notifyEnabled {
      description = "Report a failed sing-box subscription refresh";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
        ExecStart = "${subscriptionFailure}/bin/sing-box-subscription-notify-failure";
      }
      // optionalAttrs cfg.notify.telegram.enable {
        # The leading dash keeps a missing token file from failing the unit:
        # the deliverer then falls back to email instead of sending nothing.
        EnvironmentFile = "-${config.sops.secrets."telegram-notifications-bot-token".path}";
      };
    };

    # Bounce the bare host to the dashboard: sing-box serves metacubexd at
    # /ui/, and the API root it would otherwise hit is a 401 without the
    # clash secret. Gated on the traefik host so a traefik-less host doesn't
    # grow a phantom traefik container.
    containers.traefik = mkIf config.${namespace}.containers.traefik.enable {
      config.services.traefik.dynamicConfigOptions.http.middlewares.sing-box-ui-redirect.redirectRegex = {
        regex = "^https://${escapeRegex cfg.host}/$";
        replacement = "https://${cfg.host}/ui/";
      };
    };

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
        {
          containerPort = cfg.transparent.port;
          hostPort = cfg.transparent.port;
          protocol = "tcp";
        }
      ];
      config = _: {
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
                # The system resolver handles household resolver failover.
                # prefer_go is load-bearing: without it sing-box 1.13's
                # "local" server asks systemd-resolved over D-Bus for
                # *per-link* nameservers, and this container only has the
                # global DNS= list — every lookup then fails with "link has
                # no DNS servers configured" and the whole proxy goes dark.
                # prefer_go routes lookups through the 127.0.0.53 stub,
                # which is where the household resolver list actually is.
                type = "local";
                tag = "adguard";
                prefer_go = true;
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
              {
                # redsocks upstream: SNI-split, see cfg.transparent
                type = "socks";
                tag = "transparent";
                listen = "0.0.0.0";
                listen_port = cfg.transparent.port;
              }
            ];
            # vless outbounds + "auto" urltest + "exit" selector come from
            # the host's subscription refresh (${outboundsFile}), installed
            # as /run/sing-box/10-outbounds.json at start; sing-box -C
            # merges every *.json in the directory.
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
                # Transparent chain: only the blocked YouTube names need
                # the exit; every other Google service (and anything the
                # sniffer could not name) goes direct from here.
                {
                  inbound = [ "transparent" ];
                  domain_suffix = cfg.transparent.proxyDomains;
                  outbound = "exit";
                }
                {
                  inbound = [ "transparent" ];
                  outbound = "direct";
                }
                # xray's old IPIfNonMatch equivalent: resolve what the
                # domain rules didn't catch (socks5h clients send names)
                # so the IP rules below still see RU-hosted hosts on
                # foreign TLDs. Uses default_domain_resolver (adguard);
                # the outbound still dials by domain name.
                { action = "resolve"; }
                # The uplink poisons plain DNS for RKN-blocked domains
                # (api.themoviedb.org -> 127.0.0.1) and adguard forwards
                # that answer, which the ip_is_private rule below would
                # send to "direct". A loopback/unspecified result is never
                # a real destination: hand it to the exit, which dials by
                # name and resolves remotely.
                {
                  ip_cidr = [
                    "127.0.0.0/8"
                    "0.0.0.0/32"
                    "::1/128"
                  ];
                  outbound = "exit";
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
                external_ui = "${metacubexd}";
                secret._secret = config.sops.secrets."sing-box/admin_password".path;
              };
              cache_file.enabled = true;
            };
          };
        };

        # "+" = run as root: the published file may still be root-owned
        # right after a refresh (the tmpfiles Z rule only runs at boot) and
        # the module's own ExecStartPre (config.json render) also runs
        # privileged.
        systemd.services.sing-box.serviceConfig.ExecStartPre = mkAfter [
          "+${outboundsInstall}/bin/sing-box-outbounds-install ${containerOutboundsFile} /run/sing-box/10-outbounds.json"
          # Validate the merged config (module render + installed
          # outbounds) so a broken file fails with a readable message
          # instead of a crash loop. Runs as the service user — same
          # dirs as ExecStart.
          "${getExe pkgs.sing-box} check -D /var/lib/sing-box -C /run/sing-box"
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
          useHostResolvConf = false;
        };
        services.resolved = {
          enable = true;
          settings.Resolve = householdDnsSettings;
        };
        system.stateVersion = "26.05";
      };
    };
  };
}
