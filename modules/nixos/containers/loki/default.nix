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

  # Loki reads a zero duration as "keep forever", and "0s", "0h", "0m" and
  # "0m0s" are all zero. Accept only a single positive Go duration.
  periodMatch = builtins.match "([0-9]+)(s|m|h|d|w)" cfg.retention.period;
  periodIsPositive = periodMatch != null && toInt (elemAt periodMatch 0) > 0;
in
{
  options.${namespace}.containers.loki = with types; {
    enable = mkBoolOpt false "Enable the loki monitoring service ;";

    retention = {
      enable = mkBoolOpt false "Delete index entries and chunks older than `retention.period` via the compactor. Off by default so enabling it is an explicit, reviewable per-host decision (the first pass deletes all history older than the period).";

      period =
        mkOpt str "720h"
          "Retention period: a single positive Go duration (e.g. `720h` = 30 days, `30d`). Retention is applied per index table, so the effective granularity is the 24h index period regardless of the exact value.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.retention.enable -> periodIsPositive;
        message = ''
          custom.containers.loki.retention.period is "${cfg.retention.period}", which is not a single
          positive Go duration. A zero duration ("0s", "0h", "0m0s", ...) means "keep forever" to Loki,
          which silently defeats the option. Retention is enabled, so set a real period — e.g. "720h"
          (30 days) or "30d" — or set retention.enable = false instead.
        '';
      }
    ];

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
        }
        // optionalAttrs cfg.retention.enable { retention_period = cfg.retention.period; };

        # Loki still parses a `table_manager` block, but its retention never
        # applied to the TSDB single-store path, so those settings did nothing.
        # For TSDB, retention is the compactor's job.
        compactor = {
          working_directory = "/var/lib/loki/compactor";
          compaction_interval = "10m";
          compactor_ring.kvstore.store = "inmemory";
        }
        // optionalAttrs cfg.retention.enable {
          retention_enabled = true;
          # Chunks are only deleted this long after they were marked, which is the
          # window for disabling retention again without data loss.
          retention_delete_delay = "2h";
          retention_delete_worker_count = 150;
          delete_request_store = "filesystem";
        };
      };
    };

  };
}
