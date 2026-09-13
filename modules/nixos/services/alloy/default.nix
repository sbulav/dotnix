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
  cfg = config.${namespace}.services.alloy;
in
{
  options.${namespace}.services.alloy = with types; {
    enable = mkBoolOpt false "Collect this host's journals and application logs";
    endpoint = mkOpt str "http://127.0.0.1:3030/loki/api/v1/push" "Loki push endpoint";
  };
  config = mkIf cfg.enable {
    services.alloy.enable = true;

    # Alloy runs as a DynamicUser and cannot read the container-owned service
    # logs under /tank (they are group/owner-only). Give it a shared read group
    # and grant that group read access via POSIX ACLs. `SupplementaryGroups` is
    # appended so the module's existing `systemd-journal` membership is kept.
    users.groups.logreaders = { };
    systemd.services.alloy.serviceConfig.SupplementaryGroups = lib.mkAfter [ "logreaders" ];

    # ACLs are applied with `setfacl` from a root oneshot rather than
    # systemd-tmpfiles `A+`: tmpfiles refuses "unsafe path transitions"
    # (/tank is owned by `sab`, the per-service dirs by container uids) so it
    # silently skipped authelia/jellyfin, and it does not recalculate the ACL
    # mask (which left jellyfin's entries `#effective:---`). Running setfacl as
    # root avoids both problems. Default ACLs are set so rotated/new log files
    # inherit access.
    systemd.services.alloy-log-acls = {
      description = "Grant logreaders group read access to container service logs";
      after = [ "zfs-mount.service" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "alloy.service" ];
      path = [ pkgs.acl ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -u
        # /tank/jellyfin is 0700 - grant traverse so its log dir is reachable.
        [ -d /tank/jellyfin ] && setfacl -m g:logreaders:x /tank/jellyfin
        # The migrated Grafana data directory is 0750. Reading its log ACL
        # also requires traversal through both parent directories.
        for d in ${escapeShellArg config.custom.containers.grafana.dataPath} ${escapeShellArg "${config.custom.containers.grafana.dataPath}/data"}; do
          [ ! -d "$d" ] || setfacl -m g:logreaders:x "$d"
        done
        for d in \
          /tank/authelia/logs \
          ${config.custom.containers.grafana.dataPath}/data/log \
          /tank/jellyfin/log \
          /tank/sing-box/logs; do
          [ -d "$d" ] || continue
          setfacl -R -m g:logreaders:rX "$d"
          setfacl -R -d -m g:logreaders:rX "$d"
        done
      '';
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.write "local" {
        endpoint {
          url = "${cfg.endpoint}"
        }
      }

      loki.relabel "journal" {
        forward_to = []
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
      }

      loki.source.journal "journal" {
        max_age       = "12h"
        labels        = {
          job  = "systemd-journal",
          host = "${config.networking.hostName}",
        }
        relabel_rules = loki.relabel.journal.rules
        forward_to    = [loki.write.local.receiver]
      }

      local.file_match "system_logs" {
        path_targets = [
          {__path__ = "/tank/traefik/logs/access.log",       job = "traefik-access-log", host = "${config.networking.hostName}"},
          {__path__ = "/tank/traefik/logs/traefik.log",      job = "traefik-log",        host = "${config.networking.hostName}"},
          {__path__ = "/tank/authelia/logs/authelia.log",    job = "authelia",           host = "${config.networking.hostName}"},
          {__path__ = "${config.custom.containers.grafana.dataPath}/data/log/grafana.log",  job = "grafana",            host = "${config.networking.hostName}"},
          {__path__ = "/tank/jellyfin/log/*.log",            job = "jellyfin",           host = "${config.networking.hostName}"},
          {__path__ = "/tank/sing-box/logs/*.log",           job = "sing-box",           host = "${config.networking.hostName}"},
        ]
      }

      loki.source.file "system" {
        targets    = local.file_match.system_logs.targets
        forward_to = [loki.write.local.receiver]
      }
    '';
  };
}
