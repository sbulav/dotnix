{
  pkgs,
  lib,
  ...
}: let
  pname = "ktalk";
  version = "3.2.0";

  # Platform-specific sources
  src =
    if pkgs.stdenv.isLinux
    then
      builtins.fetchurl {
        url = "https://st.ktalk.host/ktalk-app/linux/${pname}${version}x86_64.AppImage";
        sha256 = "1yaiyg8cfxyvb585xfpwlji2k2cmmd3skn47chgh74ddpp1jxwgx";
      }
    else
      builtins.fetchurl {
        url = "https://st.ktalk.host/ktalk-app/mac/ktalk.${version}-mac.dmg";
        sha256 = "1lk0ssbkjx3wg7ygwgagkm33c2c99yv1psb86i8dawk0bd3ymjzk";
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
    maintainers = with maintainers; [sbulav];
    platforms = ["x86_64-linux" "x86_64-darwin" "aarch64-darwin"];
  };
  # Linux-specific: Desktop item for AppImage
  desktopItem = pkgs.makeDesktopItem {
    name = "ktalk";
    desktopName = "ktalk";
    comment = "Kontur.Talk";
    icon = "ktalk";
    exec = "ktalk %U";
    categories = ["VideoConference"];
    mimeTypes = ["x-scheme-handler/ktalk"];
  };

  # Linux-specific: Extract AppImage contents
  appimageContents = pkgs.appimageTools.extractType2 {
    inherit pname version src meta;
  };
in
  if pkgs.stdenv.isLinux
  then
    pkgs.appimageTools.wrapType2 rec {
      inherit pname version src desktopItem;

      extraInstallCommands = ''
        source "${pkgs.makeWrapper}/nix-support/setup-hook"

        # Create a wrapper that runs the binary in a detached session
        wrapProgram $out/bin/${pname} \
          --run "setsid $out/bin/.${pname}-wrapped \"\$@\" >/dev/null 2>&1 </dev/null &" \
          --run "exit 0"

        mkdir -p $out/share/applications/
        cp ${desktopItem}/share/applications/*.desktop $out/share/applications/
        cp -r ${appimageContents}/usr/share/icons/ $out/share/icons/

        runHook postInstall
      '';
    }
  else
    pkgs.stdenv.mkDerivation rec {
      inherit pname version meta src;

      sourceRoot = "Толк.app"; # Matches the .dmg volume name

      unpackPhase = ''
        tmp=$(mktemp -d)
        /usr/bin/hdiutil attach "${src}" -mountpoint "$tmp" -nobrowse -quiet
        cp -R "$tmp"/* ./

        /usr/bin/hdiutil detach "$tmp" -quiet
        rm -rf "$tmp"
      '';

      installPhase = ''
        mkdir -p $out/Applications/Толк.app
        cp -R "Contents" $out/Applications/Толк.app/
      '';
    }
