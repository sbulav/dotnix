{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.interface;
  userHome = config.users.users.${config.custom.user.name}.home;
in
{
  options.system.interface.enable = mkBoolOpt false "Whether to configure the macOS desktop interface.";

  config = mkIf cfg.enable {
    system.defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
      };

      dock = {
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.2;
        expose-animation-duration = 0.1;
        mineffect = "scale";
        minimize-to-application = true;
        mru-spaces = false;
        orientation = "bottom";
        persistent-apps = [
          "/System/Applications/Launchpad.app"
          "/System/Applications/System Settings.app"
          "/Applications/Толк.app"
          "/Applications/Firefox.app"
          "/System/Applications/Mail.app"
          "${userHome}/Applications/Home Manager Apps/WezTerm.app"
        ];
        show-process-indicators = true;
        show-recents = false;
        tilesize = 50;
        wvous-tl-corner = 2;
        wvous-tr-corner = 12;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv";
        FXRemoveOldTrashItems = true;
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
        _FXShowPosixPathInTitle = true;
        _FXSortFoldersFirst = true;
      };

      loginwindow.GuestEnabled = false;

      screencapture = {
        disable-shadow = true;
        location = "${userHome}/Pictures/screenshots";
        type = "png";
      };

      spaces.spans-displays = false;
    };
  };
}
