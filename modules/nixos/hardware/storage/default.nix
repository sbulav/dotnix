{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.hardware.storage;
in
{
  options.hardware.storage = {
    enable = mkBoolOpt false "Whether to enable storage I/O scheduler and queue tuning";
  };

  config = mkIf cfg.enable {
    hardware.block = {
      defaultScheduler = mkDefault "kyber";
      defaultSchedulerRotational = mkDefault "bfq";
    };

    services.fstrim.enable = mkDefault true;

    # Queue depth / readahead per device class. KERNEL!="*p*" keeps the
    # NVMe rules off partitions (nvme0n1p1) — queue attrs live on the disk.
    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", KERNEL!="*p*", ATTR{queue/nr_requests}="32"
      ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", KERNEL!="*p*", ATTR{queue/read_ahead_kb}="128"
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="256"
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/nr_requests}="64"
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="1024"
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/nr_requests}="256"
    '';
  };
}
