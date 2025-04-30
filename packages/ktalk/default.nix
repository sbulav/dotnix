{
  pkgs,
  lib,
  ...
}: let
  pname = "ktalk";
  version = "3.0.0";

  src = builtins.fetchurl {
    url = "https://st.ktalk.host/ktalk-app/linux/${pname}${version}x86_64.AppImage";
    sha256 = "0sb7n49kv0kwjby7sbp959jg0hhb6k0dygz7i2wv5rh58q01cy2a";
  };
  # Install and register the .desktop entry
  desktopItem = pkgs.makeDesktopItem {
    name = "ktalk";
    desktopName = "ktalk";
    comment = "Kontur.Talk";
    icon = "ktalk";
    exec = "ktalk %U";
    categories = ["VideoConference"];
    mimeTypes = ["x-scheme-handler/ktalk"];
  };
  appimageContents = pkgs.appimageTools.extractType2 {
    inherit
      pname
      version
      src
      ;
  };
in
  pkgs.appimageTools.wrapType2 rec {
    inherit
      pname
      desktopItem
      version
      src
      ;

    extraInstallCommands = ''
      source "${pkgs.makeWrapper}/nix-support/setup-hook"

      # now write a new wrapper that:
      #  1. runs the real binary in a detached session, redirecting all IO to /dev/null
      #  2. immediately exits (so you don’t block your terminal or the desktop)
      wrapProgram $out/bin/${pname} \
        --run "setsid $out/bin/.${pname}-wrapped \"\$@\" >/dev/null 2>&1 </dev/null &" \
        --run "exit 0"

      mkdir -p $out/share/applications/
      cp ${desktopItem}/share/applications/*.desktop $out/share/applications/
      cp -r ${appimageContents}/usr/share/icons/ \
            $out/share/icons/

      runHook postInstall
    '';

    meta = with lib; {
      description = ''
        Kontur talk, communication platform
      '';

      longDescription = ''
        A space for communication and teamwork

        It combines hangouts, chat rooms, webinars, online whiteboards and an
        application for meeting rooms. Allows you to capture and save the result of
        communications.
      '';

      homepage = "https://kontur.ru/talk";
      license = licenses.unlicense;
      maintainers = with maintainers; [sbulav];
      platforms = ["x86_64-linux"];
    };
  }
