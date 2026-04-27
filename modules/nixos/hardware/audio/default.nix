{
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.hardware.audio;
in
{
  options.hardware.audio = with types; {
    enable = mkBoolOpt false "Enable pipewire";
    softMixer.enable = mkBoolOpt false "Whether to force WirePlumber to use software volume control for ALSA devices.";
  };

  config = mkIf cfg.enable {
    security.rtkit.enable = true;
    services.pipewire = {
      alsa.enable = true;
      alsa.support32Bit = true;
      audio.enable = true;
      enable = true;
      jack.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;

      extraConfig.pipewire."99-akg-mic-fix" = {
        context.properties = {
          default.clock.rate = 48000;
          default.clock.quantum = 256;
          default.clock.min-quantum = 256;
          default.clock.max-quantum = 256;
        };
      };

      wireplumber.extraConfig = mkIf cfg.softMixer.enable {
        "99-alsa-soft-mixer" = {
          monitor.alsa.rules = [
            {
              matches = [
                {
                  "device.name" = "~alsa_card.*";
                }
              ];
              actions.update-props = {
                "api.alsa.soft-mixer" = true;
              };
            }
          ];
        };
      };
    };
    programs.noisetorch.enable = false;

    environment.systemPackages = with pkgs; [
      pavucontrol
      pulsemixer
      helvum
    ];
  };
}
