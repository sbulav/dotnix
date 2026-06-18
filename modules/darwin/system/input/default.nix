{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.input;
in
{
  options.system.input.enable = mkBoolOpt false "Whether to configure macOS keyboard and trackpad settings.";

  config = mkIf cfg.enable {
    system.defaults = {
      NSGlobalDomain = {
        AppleKeyboardUIMode = 3;
        ApplePressAndHoldEnabled = false;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        "com.apple.keyboard.fnState" = true;
        "com.apple.swipescrolldirection" = false;
      };

      trackpad = {
        Clicking = true;
        TrackpadCornerSecondaryClick = 0;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
      };
    };
  };
}
