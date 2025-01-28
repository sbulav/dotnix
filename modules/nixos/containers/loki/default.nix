{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.loki;
in {
  options.${namespace}.containers.loki = with types; {
    enable = mkBoolOpt false "Enable the loki monitoring service ;";
  };

  config = mkIf cfg.enable {
    # Allow grafana to read Loki DS via trusted interface
    networking.firewall.trustedInterfaces = ["ve-grafana"];
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

    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 3031;
          grpc_listen_port = 0;
        };
        positions = {
          filename = "/tmp/positions.yaml";
        };
        clients = [
          {
            url = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}/loki/api/v1/push";
          }
        ];
        scrape_configs = [
          {
            job_name = "journal";
            journal = {
              max_age = "12h";
              labels = {
                job = "systemd-journal";
                host = config.system.name";
              };
            };
            relabel_configs = [
              {
                source_labels = ["__journal__systemd_unit"];
                target_label = "unit";
              }
            ];
          }
          {
            job_name = "system";
            pipeline_stages = [];
            static_configs = [
              {
                labels = {
                  job = "traefik-access-log";
                  host = "${config.system.name}";
                  __path__ = "/tank/traefik/logs/access.log";
                };
              }
              {
                labels = {
                  job = "traefik-log";
                  host = "${config.system.name}";
                  __path__ = "/tank/traefik/logs/traefik.log";
                };
              }
              {
                labels = {
                  job = "authelia";
                  host = "${config.system.name}";
                  __path__ = "/tank/authelia/logs/authelia.log";
                };
              }
              {
                labels = {
                  job = "grafana";
                  host = "${config.system.name}";
                  __path__ = "/tank/grafana/data/log/grafana.log";
                };
              }
              {
                labels = {
                  job = "jellyfin";
                  host = "${config.system.name}";
                  __path__ = "/tank/jellyfin/log/*.log";
                };
              }
              {
                labels = {
                  job = "v2raya";
                  host = "${config.system.name}";
                  __path__ = "/tank/v2raya/logs/*.log";
                };
              }
            ];
          }
        ];
      };
      # extraFlags
    };
  };
}
