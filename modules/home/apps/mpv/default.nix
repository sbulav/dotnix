{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.apps.mpv;
in
{
  options.custom.apps.mpv = {
    enable = mkBoolOpt false "Whether to enable mpv with safe hardware decoding";
  };

  config = mkIf cfg.enable {
    programs.mpv = {
      enable = true;
      # Probe only the copy-free, known-good decode paths (nvdec on mz's
      # NVIDIA card, VA-API on nz's Intel iGPU) and fall back to software
      # quietly. Not "vaapi": that would silently drop hardware decode on mz.
      config.hwdec = "auto-safe";
    };
  };
}
