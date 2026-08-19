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
