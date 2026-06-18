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
        # Appearance
        AppleInterfaceStyle = "Dark";
        AppleShowScrollBars = "WhenScrolling";

        AppleShowAllExtensions = true;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;

        # Expand save / print dialogs by default
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        PMPrintingExpandedStateForPrint = true;
        PMPrintingExpandedStateForPrint2 = true;

        # Save to disk, not iCloud, by default
        NSDocumentSaveNewDocumentsToCloud = false;

        # Snappier window resize animations
        NSWindowResizeTime = 0.001;

        # Locale: 24-hour time, metric units
        AppleICUForce24HourTime = true;
        AppleMeasurementUnits = "Centimeters";
        AppleMetricUnits = 1;
        AppleTemperatureUnit = "Celsius";
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
        NewWindowTarget = "Home";
        QuitMenuItem = true;
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowMountedServersOnDesktop = true;
        ShowRemovableMediaOnDesktop = true;
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

      # Show battery percentage in the menu bar
      controlcenter.BatteryShowPercentage = true;

      # Stage Manager off; don't hide windows when clicking the wallpaper
      WindowManager = {
        GloballyEnabled = false;
        EnableStandardClickToShowDesktop = false;
      };

      # Don't nag with "are you sure you want to open this app?" for every download
      LaunchServices.LSQuarantine = false;
    };
  };
}
