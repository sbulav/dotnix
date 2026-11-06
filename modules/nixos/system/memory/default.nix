{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.memory;
in
{
  options.system.memory = with types; {
    enable = mkBoolOpt false "Whether to enable memory management tuning (zram, oomd, KSM)";
    zram.enable = mkBoolOpt true "Whether to enable zram compressed swap";
    oomd.enable = mkBoolOpt true "Whether to enable systemd-oomd userspace OOM killing";
    ksm.enable = mkBoolOpt true "Whether to enable kernel samepage merging";
    ksm.sleep = mkOpt (nullOr int) 100 "KSM sleep interval between scans in milliseconds";
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.zram.enable {
      zramSwap = {
        enable = true;
        algorithm = mkDefault "zstd";
        memoryPercent = mkDefault 100;
        priority = mkDefault 100;
      };

      # zram swap is cheap to use, so reclaim aggressively into it and keep
      # the page cache (Omarchy 99-omarchy-sysctl.conf, pop-os/zram tuning).
      boot.kernel.sysctl = {
        "vm.swappiness" = mkDefault 150;
        # One page per swap-in: zram has no seek cost, so read-ahead is waste.
        "vm.page-cluster" = mkDefault 0;
        "vm.vfs_cache_pressure" = mkDefault 50;
        # Do not boost watermarks after fragmentation; a flat 1.25 % scale
        # avoids kswapd thrashing on 16-64 GiB desktops.
        "vm.watermark_boost_factor" = mkDefault 0;
        "vm.watermark_scale_factor" = mkDefault 125;
        # Absolute dirty thresholds (64 MiB / 256 MiB) instead of RAM
        # percentages so a big copy cannot pile up gigabytes of dirty pages.
        "vm.dirty_background_bytes" = mkDefault 67108864;
        "vm.dirty_bytes" = mkDefault 268435456;
        "vm.dirty_writeback_centisecs" = mkDefault 1500;
      };
    })

    (mkIf cfg.oomd.enable {
      systemd.oomd = {
        enable = true;
        # Slice-level policy is opt-in per host/module (desktop enables
        # its own app.slice limits in desktop/addons/system-polish).
        enableRootSlice = mkDefault false;
        enableSystemSlice = mkDefault false;
        enableUserSlices = mkDefault false;
        settings.OOM = {
          DefaultMemoryPressureDurationSec = "20s";
          SwapUsedLimit = "90%";
        };
      };
      # oomd reads swap state; make sure zram/swap devices exist first.
      systemd.services.systemd-oomd.after = [ "swap.target" ];
    })

    (mkIf cfg.ksm.enable {
      hardware.ksm = {
        enable = true;
        sleep = cfg.ksm.sleep;
      };
    })
  ]);
}
