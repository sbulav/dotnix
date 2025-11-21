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
    };
    programs.noisetorch.enable = false;

    environment.systemPackages = with pkgs; [
      pavucontrol
      pulsemixer
      helvum
    ];
  };
}
