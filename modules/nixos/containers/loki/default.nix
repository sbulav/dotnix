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
  cfg = config.${namespace}.containers.loki;
in
{
  options.${namespace}.containers.loki = with types; {
    enable = mkBoolOpt false "Enable the loki monitoring service ;";
  };

  config = mkIf cfg.enable {
    # Allow grafana to read Loki DS via trusted interface
    networking.firewall.trustedInterfaces = [ "ve-grafana" ];
    services.loki = {
      enable = true;
      configuration = {
        server.http_listen_port = 3030;
        server.http_listen_address = "0.0.0.0";
        auth_enabled = false;
        analytics.reporting_enabled = false;
        tracing.enabled = false;

        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore = {
                store = "inmemory";
              };
              replication_factor = 1;
            };
          };
          chunk_idle_period = "1h";
          max_chunk_age = "1h";
          chunk_target_size = 999999;
          chunk_retain_period = "30s";
        };

        schema_config = {
          configs = [
            {
              from = "2024-07-26";
              # store = "boltdb-shipper";
              object_store = "filesystem";
              store = "tsdb";
              schema = "v13"; # Use a valid schema version
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/boltdb-shipper-active";
            cache_location = "/var/lib/loki/boltdb-shipper-cache";
            cache_ttl = "24h";
          };

          filesystem = {
            directory = "/var/lib/loki/chunks";
          };
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        table_manager = {
          retention_deletes_enabled = false;
          retention_period = "0s";
        };

        compactor = {
          working_directory = "/var/lib/loki";
          compactor_ring = {
            kvstore = {
              store = "inmemory";
            };
          };
        };
      };
    };

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
        for d in \
          /tank/authelia/logs \
          /tank/grafana/data/log \
          /tank/jellyfin/log \
          /tank/v2raya/logs; do
          [ -d "$d" ] || continue
          setfacl -R -m g:logreaders:rX "$d"
          setfacl -R -d -m g:logreaders:rX "$d"
        done
      '';
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.write "local" {
        endpoint {
          url = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}/loki/api/v1/push"
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
          host = "${config.system.name}",
        }
        relabel_rules = loki.relabel.journal.rules
        forward_to    = [loki.write.local.receiver]
      }

      local.file_match "system_logs" {
        path_targets = [
          {__path__ = "/tank/traefik/logs/access.log",       job = "traefik-access-log", host = "${config.system.name}"},
          {__path__ = "/tank/traefik/logs/traefik.log",      job = "traefik-log",        host = "${config.system.name}"},
          {__path__ = "/tank/authelia/logs/authelia.log",    job = "authelia",           host = "${config.system.name}"},
          {__path__ = "/tank/grafana/data/log/grafana.log",  job = "grafana",            host = "${config.system.name}"},
          {__path__ = "/tank/jellyfin/log/*.log",            job = "jellyfin",           host = "${config.system.name}"},
          {__path__ = "/tank/v2raya/logs/*.log",             job = "v2raya",             host = "${config.system.name}"},
        ]
      }

      loki.source.file "system" {
        targets    = local.file_match.system_logs.targets
        forward_to = [loki.write.local.receiver]
      }
    '';
  };
}
