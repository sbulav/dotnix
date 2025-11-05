{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  inherit (lib) mkIf mkMerge;
  inherit (lib.${namespace}) mkBoolOpt;

  cfg = config.hardware.gpu.intel;
in
{
  options.hardware.gpu.intel = {
    enable = mkBoolOpt false "Whether or not to enable support for Intel GPU (Arc, Iris, UHD).";
    enableArcSupport = mkBoolOpt true "Enable additional support for Intel Arc GPUs (DG2).";
  };

  config = mkIf cfg.enable {
    boot = {
      initrd.kernelModules = [ "i915" ];
      kernelModules = [ "i915" ];

      kernelParams = [
        "i915.enable_guc=2"
      ]
      ++ lib.optionals cfg.enableArcSupport [
        "i915.force_probe=*"
      ];
    };

    environment.systemPackages = with pkgs; [
      intel-gpu-tools
      nvtopPackages.intel
    ];

    environment.sessionVariables = {
      "LIBVA_DRIVER_NAME" = "iHD";
      "ANV_ENABLE_PIPELINE_CACHE" = "1";
      "MESA_LOADER_DRIVER_OVERRIDE" = "iris";
    };

    hardware.graphics = {
      extraPackages = with pkgs; [
        intel-media-driver
        intel-compute-runtime
        vpl-gpu-rt
        level-zero

        mesa

        intel-vaapi-driver
        libvdpau-va-gl

        vulkan-tools
        vulkan-loader
        vulkan-validation-layers
        vulkan-extension-layer
      ];

      extraPackages32 = with pkgs.pkgsi686Linux; [
        intel-media-driver

        mesa

        intel-vaapi-driver
        libvdpau-va-gl

        vulkan-loader
      ];
    };

    nixpkgs.config.packageOverrides = pkgs: {
      intel-vaapi-driver = pkgs.intel-vaapi-driver.override { enableHybridCodec = true; };
    };

    services.xserver.videoDrivers = lib.mkDefault [
      "modesetting"
      "intel"
    ];
  };
}
