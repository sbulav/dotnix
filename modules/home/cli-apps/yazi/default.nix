{
  config,
  lib,
  options,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.cli-apps.yazi;

  # Inside a herdr pane, TERM_PROGRAM=WezTerm and WEZTERM_EXECUTABLE leak
  # through from the host terminal, and herdr sets no TMUX/ZELLIJ marker.
  # yazi's Brand::from_env() trusts them, short-circuits terminal probing
  # entirely, and picks the iTerm2 inline-image adapter — but herdr's VT
  # (vendored libghostty-vt) drops `OSC 1337;File=` on the floor
  # ("unimplemented OSC 1337"), so a PDF preview writes ~90 KB of base64 in
  # one flush into a pane that discards it, stalling yazi while it holds the
  # TTY lock in raw mode. That reads as the whole terminal hanging.
  #
  # Clearing the leak makes yazi probe instead. herdr answers XTVERSION with
  # "libghostty", which yazi substring-matches as ghostty and maps to the
  # Kitty graphics adapter — the one image protocol herdr implements, and it
  # chunks into 4 KB APC frames instead of one huge blob. That needs
  # experimental.kitty_graphics in custom.cli-apps.herdr.
  #
  # The compositor sockets go too: if the XTVERSION match ever stops holding,
  # yazi's adapter list comes back empty and it falls through to ueberzugpp,
  # which is not installed. Without those vars it picks chafa instead, which
  # is already on yazi's wrapper PATH.
  unleakHerdr = ''
    if [ -n "''${HERDR_ENV-}" ]; then
      unset TERM_PROGRAM TERM_PROGRAM_VERSION WEZTERM_EXECUTABLE
      unset HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK NIRI_SOCKET WAYFIRE_SOCKET
    fi
  '';

  yaziPackage = pkgs.symlinkJoin {
    name = "yazi-herdr-aware-${getVersion pkgs.yazi}";
    paths = [ pkgs.yazi ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/yazi --run ${escapeShellArg unleakHerdr}
    '';
  };
in
{
  options.custom.cli-apps.yazi = {
    enable = mkEnableOption "Yazi Terminal File manager";
  };

  config = mkIf cfg.enable {
    programs.yazi = {
      enable = true;
      package = yaziPackage;
      shellWrapperName = "yy";

      enableBashIntegration = true;
      enableFishIntegration = true;
      enableNushellIntegration = true;
      enableZshIntegration = true;

      settings = {
        mgr = {
          layout = [
            1
            3
            4
          ];
          linemode = "size";
          show_hidden = false;
          show_symlink = true;
          sort_by = "alphabetical";
          sort_dir_first = true;
          sort_reverse = false;
          sort_sensitive = false;
        };
      };
    };

    xdg.configFile = {
      "yazi" = {
        source = lib.cleanSourceWith {
          src = lib.cleanSource ./configs/.;
        };

        recursive = true;
      };
    };
  };
}
