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
  cfg = config.custom.apps.pcmanfm-qt;
  package = pkgs.lxqt.pcmanfm-qt;
  associations = {
    "inode/directory" = [ "pcmanfm-qt.desktop" ];
  };

  # Firefox's "Show in Folder" uses FileManager1 before falling back to
  # the directory MIME handler. PCManFM-Qt implements it, but does not ship
  # a D-Bus activation file. Start on demand without opening an extra home
  # window or enabling LXQt's desktop/icon manager.
  fileManagerService = pkgs.writeTextDir "share/dbus-1/services/org.freedesktop.FileManager1.service" ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${lib.getExe package} --daemon-mode
  '';

  # libfm-qt's built-in terminal list lacks WezTerm. Teach it both how to
  # open a shell here and how to run a Terminal=true desktop application.
  terminalDefinition = pkgs.writeTextDir "share/libfm-qt/terminals.list" ''
    [wezterm]
    desktop_id=org.wezfurlong.wezterm.desktop
    launch=start --cwd .
    open_arg=start --cwd . --
  '';
in
{
  options.custom.apps.pcmanfm-qt = with types; {
    enable = mkBoolOpt false "Whether to use PCManFM-Qt as the graphical file manager.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      package
      terminalDefinition
    ];
    environment.pathsToLink = [ "/share/libfm-qt" ];

    # Seed standalone mode with installed icons and our usual terminal;
    # upstream defaults to the Oxygen icon theme and Xterm outside LXQt.
    # PCManFM-Qt copies these defaults into its writable per-user profile.
    environment.etc."xdg/pcmanfm-qt/default/settings.conf".source =
      (pkgs.formats.ini { }).generate "pcmanfm-qt-settings.conf"
        {
          System = {
            FallbackIconThemeName = "Adwaita";
            Terminal = "wezterm";
          };
        };

    services = {
      dbus.packages = [ fileManagerService ];
      # libfm-qt uses GVfs for Trash, remote filesystems and volume handling.
      gvfs.enable = true;
    };

    xdg.mime = {
      enable = true;
      defaultApplications = mapAttrs (_: mkDefault) associations;
      addedAssociations = associations;
    };
  };
}
