{
  lib,
  runCommand,
  prometheus,
  writeText,
  ...
}:
# Proves the disk-health alert semantics: the A query of each Grafana rule is
# pulled out of rules.json by uid and wrapped with its C threshold into a
# Prometheus alerting rule, then fed recorded-shaped series with
# `promtool test rules`. Grafana's `for` and NoData handling are not modelled.
let
  grafanaRules = builtins.fromJSON (
    builtins.readFile (lib.snowfall.fs.get-file "modules/nixos/containers/grafana/alerting/rules.json")
  );

  operators = {
    gt = ">";
    lt = "<";
  };

  alertFor =
    uid:
    let
      find = what: pred: lib.findFirst pred (throw "disk-health-alerts: ${uid}: no ${what}");
      rule = find "Grafana rule" (r: r.uid == uid) grafanaRules;
      query = find "query A" (q: q.refId == "A") rule.data;
      threshold = find "threshold C" (q: q.refId == "C") rule.data;
      inherit (lib.head threshold.model.conditions) evaluator;
    in
    {
      alert = uid;
      expr = "(${query.model.expr}) ${operators.${evaluator.type}} ${toString (lib.head evaluator.params)}";
    };

  uids = {
    errorLog = "aeaje2nu3xh4wd";
    sectors = "smartsectorgrowth";
    nvme = "smartnvmemediagrowth";
    pool = "ceajpo02hmlmoa";
    vdev = "zfsvdeverrors";
    scrubStale = "zfsscrubstale";
    scanErrors = "zfsscanerrors";
    exporter = "zfsstatusexporter";
  };

  rules = writeText "disk-health-alerts.rules.json" (
    builtins.toJSON {
      groups = [
        {
          name = "disk-health";
          rules = map alertFor (lib.attrValues uids);
        }
      ];
    }
  );

  # Series helpers; label sets follow what the node and smartctl jobs on
  # beez attach (host and instance are the hostname).
  common = host: ''job="smartctl",host="${host}",instance="${host}"'';
  zfsLabels = ''job="node",host="zanoza",instance="zanoza",pool="tank"'';

  disk =
    {
      host ? "zanoza",
      device,
      serial,
      model ? "ST4000NM0035-1V4107",
      values,
    }:
    {
      series = ''smartctl_device{${common host},device="${device}",serial_number="${serial}",model_name="${model}"}'';
      inherit values;
    };
  attribute = device: name: values: {
    series = ''smartctl_device_attribute{${common "zanoza"},device="${device}",attribute_id="0",attribute_name="${name}",attribute_value_type="raw"}'';
    inherit values;
  };
  sdc =
    values:
    disk {
      device = "sdc";
      serial = "ZC1AHL18";
      inherit values;
    };
  sdcAlert = {
    host = "zanoza";
    device = "sdc";
    serial_number = "ZC1AHL18";
    model_name = "ST4000NM0035-1V4107";
  };

  noAlert = alertname: eval_time: {
    inherit alertname eval_time;
    exp_alerts = [ ];
  };
  alertWith = alertname: eval_time: labels: {
    inherit alertname eval_time;
    exp_alerts = [ { exp_labels = labels; } ];
  };

  tests = [
    # zanoza's sdc today: 10 reallocated sectors and 50 CRC errors, steady.
    {
      interval = "1h";
      input_series = [
        (sdc "1x48")
        (attribute "sdc" "Reallocated_Sector_Ct" "10x48")
        (attribute "sdc" "UDMA_CRC_Error_Count" "50x48")
        {
          series = ''smartctl_device_error_log_count{${common "zanoza"},device="sdc",error_log_type="summary"}'';
          values = "0x48";
        }
      ];
      alert_rule_test = [
        (noAlert uids.sectors "25h")
        (noAlert uids.errorLog "25h")
      ];
    }
    # One more reallocated sector alerts for a day, naming the disk by serial.
    {
      interval = "1h";
      input_series = [
        (sdc "1x72")
        (attribute "sdc" "Reallocated_Sector_Ct" "10x24 11x48")
        (attribute "sdc" "UDMA_CRC_Error_Count" "50x72")
      ];
      alert_rule_test = [
        (noAlert uids.sectors "23h")
        (alertWith uids.sectors "25h" (sdcAlert // { attribute_name = "Reallocated_Sector_Ct"; }))
        (noAlert uids.sectors "49h")
      ];
    }
    # Two disks swap sdX letters across a reboot: comparing by device alone
    # would read sdd as 0 -> 10, the serial join compares each disk with itself.
    {
      interval = "1h";
      input_series = [
        (sdc "1x24 _x24")
        (disk {
          device = "sdd";
          serial = "ZC1AHL18";
          values = "_x25 1x23";
        })
        (disk {
          device = "sdd";
          serial = "ZC13N2EF";
          values = "1x24 _x24";
        })
        (disk {
          device = "sdc";
          serial = "ZC13N2EF";
          values = "_x25 1x23";
        })
        (attribute "sdc" "Reallocated_Sector_Ct" "10x24 0x24")
        (attribute "sdd" "Reallocated_Sector_Ct" "0x24 10x24")
      ];
      alert_rule_test = [ (noAlert uids.sectors "26h") ];
    }
    # SMART error log growth on zanoza, NVMe media errors on beez.
    {
      interval = "1h";
      input_series = [
        (sdc "1x48")
        {
          series = ''smartctl_device_error_log_count{${common "zanoza"},device="sdc",error_log_type="summary"}'';
          values = "0x24 1x24";
        }
        (disk {
          host = "beez";
          device = "nvme0";
          serial = "S5GXNX0T000000";
          model = "Samsung SSD 980 1TB";
          values = "1x48";
        })
        {
          series = ''smartctl_device_media_errors{${common "beez"},device="nvme0"}'';
          values = "0x24 2x24";
        }
      ];
      alert_rule_test = [
        (alertWith uids.errorLog "25h" sdcAlert)
        (alertWith uids.nvme "25h" {
          host = "beez";
          device = "nvme0";
          serial_number = "S5GXNX0T000000";
          model_name = "Samsung SSD 980 1TB";
        })
      ];
    }
    # Pool state from node_exporter's zfs collector.
    {
      interval = "5m";
      input_series = [
        {
          series = ''node_zfs_zpool_state{job="node",host="zanoza",instance="zanoza",zpool="tank",state="online"}'';
          values = "1x6 0x6";
        }
        {
          series = ''node_zfs_zpool_state{job="node",host="zanoza",instance="zanoza",zpool="tank",state="degraded"}'';
          values = "0x6 1x6";
        }
      ];
      alert_rule_test = [
        (noAlert uids.pool "20m")
        (alertWith uids.pool "45m" {
          host = "zanoza";
          zpool = "tank";
        })
      ];
    }
    # A checksum error on one member; its other counters stay at 0.
    {
      interval = "5m";
      input_series = [
        {
          series = ''zfs_vdev_errors{${zfsLabels},vdev="wwn-0x5000c500790690fc-part2",type="checksum"}'';
          values = "0x6 12x6";
        }
        {
          series = ''zfs_vdev_errors{${zfsLabels},vdev="wwn-0x5000c500790690fc-part2",type="read"}'';
          values = "0x12";
        }
      ];
      alert_rule_test = [
        (noAlert uids.vdev "20m")
        (alertWith uids.vdev "45m" {
          host = "zanoza";
          pool = "tank";
          vdev = "wwn-0x5000c500790690fc-part2";
          type = "checksum";
        })
      ];
    }
    # Last scrub ended at t=0: fine on day 39, overdue on day 41.
    {
      interval = "1d";
      input_series = [
        {
          series = ''zfs_pool_scan_end_timestamp_seconds{${zfsLabels},function="scrub"}'';
          values = "0x50";
        }
        {
          series = ''zfs_pool_scan_running{${zfsLabels},function="scrub"}'';
          values = "0x50";
        }
        {
          series = "zfs_pool_data_errors{${zfsLabels}}";
          values = "0x50";
        }
      ];
      alert_rule_test = [
        (noAlert uids.scrubStale "39d")
        (alertWith uids.scrubStale "41d" {
          host = "zanoza";
          pool = "tank";
        })
      ];
    }
    # Never scanned (no scan_stats) alerts; a first resilver in flight does not.
    {
      interval = "1d";
      input_series = [
        {
          series = "zfs_pool_data_errors{${zfsLabels}}";
          values = "0x4";
        }
        {
          series = ''zfs_pool_scan_running{${zfsLabels},function="resilver"}'';
          values = "_x2 1x2";
        }
      ];
      alert_rule_test = [
        (alertWith uids.scrubStale "1d" {
          host = "zanoza";
          pool = "tank";
        })
        (noAlert uids.scrubStale "3d")
      ];
    }
    # The last scrub repaired or found errors.
    {
      interval = "1d";
      input_series = [
        {
          series = ''zfs_pool_scan_errors{${zfsLabels},function="scrub"}'';
          values = "0 3";
        }
      ];
      alert_rule_test = [
        (noAlert uids.scanErrors "0d")
        (alertWith uids.scanErrors "1d" {
          host = "zanoza";
          pool = "tank";
          function = "scrub";
        })
      ];
    }
    # Exporter health: a failed run alerts at once, a stopped timer after 30m.
    {
      interval = "1m";
      input_series = [
        {
          series = "zfs_status_exporter_success{${zfsLabels}}";
          values = "1x10 0x50";
        }
        {
          series = "zfs_status_exporter_last_run_timestamp_seconds{${zfsLabels}}";
          values = "0+60x60";
        }
      ];
      alert_rule_test = [
        (noAlert uids.exporter "5m")
        (alertWith uids.exporter "20m" { })
      ];
    }
    {
      interval = "1m";
      input_series = [
        {
          series = "zfs_status_exporter_success{${zfsLabels}}";
          values = "1x60";
        }
        {
          series = "zfs_status_exporter_last_run_timestamp_seconds{${zfsLabels}}";
          values = "0x60";
        }
      ];
      alert_rule_test = [
        (noAlert uids.exporter "20m")
        (alertWith uids.exporter "40m" { })
      ];
    }
  ];

  testFile = writeText "disk-health-alerts.test.json" (
    builtins.toJSON {
      rule_files = [ "${rules}" ];
      evaluation_interval = "1m";
      inherit tests;
    }
  );
in
runCommand "disk-health-alerts" { nativeBuildInputs = [ prometheus.cli ]; } ''
  promtool check rules ${rules}
  promtool test rules ${testFile}
  touch "$out"
''
