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
      version
      src
      ;

    extraInstallCommands = ''
      source "${pkgs.makeWrapper}/nix-support/setup-hook"

      wrapProgram $out/bin/${pname}

      install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications/

      # Directly use Logo png without conversion
      install -m  444 -D ${appimageContents}/usr/share/icons/hicolor/512x512/apps/${pname}.png $out/share/icons/hicolor/512x512/apps/${pname}.png

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
