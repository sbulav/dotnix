{
  pkgs,
  lib,
  ...
}:
let
  pname = "ktalk";

  # Versions diverge per platform; hashes come straight from the
  # electron-updater manifests (sha512 is already SRI base64):
  #   https://st.ktalk.host/ktalk-app/linux/latest-linux.yml
  #   https://st.ktalk.host/ktalk-app/mac/latest-mac.yml
  linux = rec {
    version = "3.6.0";
    src = pkgs.fetchurl {
      url = "https://st.ktalk.host/ktalk-app/linux/${pname}${version}x86_64.AppImage";
      hash = "sha512-0olnUkf+j1grGEw1XV+47m47klLoRIejFgyfiy3Pp0+L0nPiy+27MA6RHnubfUEKsCeyMNa/rnK4Mf+IlK9myg==";
    };
  };

  darwin = rec {
    version = "3.6.1";
    src = pkgs.fetchurl {
      url = "https://st.ktalk.host/ktalk-app/mac/ktalk.${version}-mac.dmg";
      hash = "sha512-wGeUTGGDo70bcR2PM7YmOrU53kMt7+AaFrmNkWksq6kqjLglhFcCyY7+Vi0GdhQ3AUIe5j1vCMBlCLDZx0nr6w==";
    };
  };

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
    license = licenses.unfree;
    maintainers = with maintainers; [ sbulav ];
    mainProgram = "ktalk";
    platforms = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };

  # Linux-specific: Desktop item for AppImage
  desktopItem = pkgs.makeDesktopItem {
    name = "ktalk";
    desktopName = "ktalk";
    comment = "Kontur.Talk";
    icon = "ktalk";
    exec = "ktalk %U";
    categories = [ "VideoConference" ];
    mimeTypes = [ "x-scheme-handler/ktalk" ];
  };

  # Linux-specific: Extract AppImage contents
  appimageContents = pkgs.appimageTools.extractType2 {
    inherit pname;
    inherit (linux) version src;
  };
in
if pkgs.stdenv.isLinux then
  pkgs.appimageTools.wrapType2 {
    inherit pname meta desktopItem;
    inherit (linux) version src;

    extraInstallCommands = ''
      mkdir -p $out/share/applications/
      cp ${desktopItem}/share/applications/*.desktop $out/share/applications/
      cp -r ${appimageContents}/usr/share/icons/ $out/share/icons/
    '';
  }
else
  pkgs.stdenv.mkDerivation {
    inherit pname meta;
    inherit (darwin) version src;

    sourceRoot = "Толк.app"; # Matches the .dmg volume name

    unpackPhase = ''
      tmp=$(mktemp -d)
      /usr/bin/hdiutil attach "$src" -mountpoint "$tmp" -nobrowse -quiet
      cp -R "$tmp"/* ./

      /usr/bin/hdiutil detach "$tmp" -quiet
      rm -rf "$tmp"
    '';

    installPhase = ''
      mkdir -p $out/Applications/Толк.app
      cp -R "Contents" $out/Applications/Толк.app/
    '';
  }
