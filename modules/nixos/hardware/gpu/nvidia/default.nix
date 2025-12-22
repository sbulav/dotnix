{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  inherit (lib) mkDefault mkIf versionOlder;
  inherit (lib.${namespace}) mkBoolOpt;
  cfg = config.hardware.gpu.nvidia;

  # use the latest possible nvidia package
  nvStable = config.boot.kernelPackages.nvidiaPackages.stable.version;
  nvBeta = config.boot.kernelPackages.nvidiaPackages.beta.version;

  nvidiaPackage =
    if (versionOlder nvBeta nvStable) then
      config.boot.kernelPackages.nvidiaPackages.stable
    else
      config.boot.kernelPackages.nvidiaPackages.beta;
in
{
  options.hardware.gpu.nvidia = {
    enable = mkBoolOpt false "Whether or not to enable support for nvidia.";
    enableCudaSupport = mkBoolOpt false "Whether or not to enable support for cuda.";
  };

  config = mkIf cfg.enable {
    boot.blacklistedKernelModules = [ "nouveau" ];

    # Critical: Configure video drivers to load NVIDIA kernel modules
    services.xserver.videoDrivers = [ "nvidia" ];

    # NVIDIA-specific environment variables for Wayland/Hyprland
    environment.sessionVariables = {
      LIBVA_DRIVER_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      NVD_BACKEND = "direct";
      # Fix screen sharing in ktalk on nvidia
      __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
    };

    environment.systemPackages = with pkgs; [
      nvfancontrol

      nvtopPackages.nvidia

      # mesa
      mesa

      # vulkan
      vulkan-tools
      vulkan-loader
      vulkan-validation-layers
      vulkan-extension-layer
      egl-wayland
    ];

    hardware = {
      nvidia = mkIf (!config.hardware.gpu.amd.enable) {
        package = mkDefault nvidiaPackage;
        modesetting.enable = mkDefault true;

        powerManagement = {
          enable = mkDefault true;
          finegrained = mkDefault false;
        };

        open = mkDefault true;
        nvidiaSettings = false;
        nvidiaPersistenced = true;
        # Note: forceFullCompositionPipeline can cause issues with Wayland
        # Disable it for Wayland compositors like Hyprland
        forceFullCompositionPipeline = false;
      };

      graphics = {
        extraPackages = with pkgs; [ nvidia-vaapi-driver ];
        extraPackages32 = with pkgs.pkgsi686Linux; [ nvidia-vaapi-driver ];
      };
    };

    nixpkgs.config.cudaSupport = cfg.enableCudaSupport;
  };
}
