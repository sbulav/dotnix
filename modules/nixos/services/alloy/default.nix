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
  c = config.${namespace}.containers;
  hostName = config.networking.hostName;

  # Application logs are collected only for services enabled on this host: a
  # disabled service's leftover directory must not keep feeding Loki under
  # this host's label. `traverse` lists parent directories the reader group
  # needs `x` on to reach the log directory.
  fileTargets =
    optionals c.traefik.enable [
      {
        path = "${c.traefik.dataPath}/logs/access.log";
        job = "traefik-access-log";
      }
      {
        path = "${c.traefik.dataPath}/logs/traefik.log";
        job = "traefik-log";
      }
    ]
    ++ optionals c.authelia.enable [
      {
        path = "${c.authelia.dataPath}/logs/authelia.log";
        job = "authelia";
      }
    ]
    ++ optionals c.grafana.enable [
      {
        path = "${c.grafana.dataPath}/data/log/grafana.log";
        job = "grafana";
        # The migrated Grafana data directory is 0750.
        traverse = [
          c.grafana.dataPath
          "${c.grafana.dataPath}/data"
        ];
      }
    ]
    ++ optionals c.jellyfin.enable [
      {
        path = "${c.jellyfin.dataPath}/log/*.log";
        job = "jellyfin";
        # /tank/jellyfin is 0700.
        traverse = [ c.jellyfin.dataPath ];
      }
    ]
    ++ optionals c.sing-box.enable [
      {
        path = "${c.sing-box.dataPath}/logs/*.log";
        job = "sing-box";
      }
    ];
  logDirs = unique (map (t: dirOf t.path) fileTargets);
  traverseDirs = unique (concatMap (t: t.traverse or [ ]) fileTargets);
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
        for d in ${escapeShellArgs traverseDirs}; do
          [ ! -d "$d" ] || setfacl -m g:logreaders:x "$d"
        done
        for d in ${escapeShellArgs logDirs}; do
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
          host = "${hostName}",
        }
        relabel_rules = loki.relabel.journal.rules
        forward_to    = [loki.write.local.receiver]
      }

      local.file_match "system_logs" {
        path_targets = [
          ${concatMapStringsSep "\n          " (
            t: ''{__path__ = "${t.path}", job = "${t.job}", host = "${hostName}"},''
          ) fileTargets}
        ]
      }

      loki.source.file "system" {
        targets    = local.file_match.system_logs.targets
        forward_to = [loki.write.local.receiver]
      }
    '';
  };
}
