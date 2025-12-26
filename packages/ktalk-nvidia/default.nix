{ pkgs, lib, ... }:
let
  pname = "ktalk-nvidia";
  version = "3.3.0";

  # NVIDIA-patched AppImage from sbulav's releases
  src = builtins.fetchurl {
    url = "https://github.com/sbulav/appimages/releases/download/v3.3.0-nvidia/ktalk-nvidia-x86_64.AppImage";
    sha256 = "1f1db885ea830f3039c2e3416a98be278c5c359075352edcf175e0340f094b19";
  };

  meta = with lib; {
    description = ''
      Kontur talk, communication platform with NVIDIA GPU support
    '';
    longDescription = ''
      A space for communication and teamwork with NVIDIA GPU support.
      This version includes fixes for virtual background and screensharing
      on NVIDIA GPUs (RTX 5070 and others).

      It combines hangouts, chat rooms, webinars, online whiteboards and an
      application for meeting rooms. Allows you to capture and save the result of
      communications.
    '';
    homepage = "https://kontur.ru/talk";
    license = licenses.unfree;
    maintainers = with maintainers; [ sbulav ];
    platforms = [ "x86_64-linux" ];
  };

  # Desktop item for AppImage
  desktopItem = pkgs.makeDesktopItem {
    name = "ktalk-nvidia";
    desktopName = "ktalk (NVIDIA)";
    comment = "Kontur.Talk with NVIDIA GPU support";
    icon = "ktalk";
    exec = "ktalk-nvidia %U";
    categories = [ "VideoConference" ];
    mimeTypes = [ "x-scheme-handler/ktalk" ];
  };

  # Extract AppImage contents
  appimageContents = pkgs.appimageTools.extractType2 {
    inherit
      pname
      version
      src
      meta
      ;
  };

  # NVIDIA-fixed wrapper script based on user's launcher
  nvidiaWrapperScript = pkgs.writeShellScriptBin "ktalk-nvidia-wrapper" ''
    #!/usr/bin/env bash
    # Fixed wrapper for Ktalk with NVIDIA on NixOS
    # Solves virtual background white screen issue

    # Set EGL vendor to NVIDIA
    export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json

    # CRITICAL: Add system NVIDIA libraries to library path
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"

    # Set EGL platform based on current session
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        echo "Detected Wayland session"
        export EGL_PLATFORM=wayland
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
    else
        echo "Detected X11 session"
        export EGL_PLATFORM=x11
    fi

    # GPU configuration for virtual background support
    export CHROMIUM_FLAGS="--use-gl=egl --enable-features=Vulkan --ignore-gpu-blocklist --disable-gpu-driver-bug-workarounds"
    export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --enable-webgl --enable-webgl2-compute-context --enable-accelerated-2d-canvas"

    # Optional debug logging (uncomment if needed)
    # export ELECTRON_ENABLE_LOGGING=1
    # export LIBGL_DEBUG=verbose

    echo "========================================="
    echo "Ktalk NVIDIA Fixed Launcher"
    echo "========================================="
    echo "Session: $XDG_SESSION_TYPE"
    echo "EGL Platform: $EGL_PLATFORM"
    echo "EGL Vendor: NVIDIA"
    echo "Library Path: /run/opengl-driver/lib"
    echo "========================================="
    echo ""
    echo "Starting Ktalk with fixed GPU configuration..."
    echo "Virtual background should now work correctly."
    echo ""

    # Run the wrapped AppImage binary
    exec "$KTALK_BINARY" "$@"
  '';
in
pkgs.appimageTools.wrapType2 rec {
  inherit
    pname
    version
    src
    desktopItem
    ;

  extraPkgs =
    pkgs: with pkgs; [
      # Ensure NVIDIA libraries are available at runtime
      nvidia-vaapi-driver
      libglvnd
      mesa
    ];

  extraInstallCommands = ''
    source "${pkgs.makeWrapper}/nix-support/setup-hook"

    # Create the main binary wrapper that calls our NVIDIA launcher
    wrapProgram $out/bin/${pname} \
      --set KTALK_BINARY "$out/bin/.${pname}-wrapped" \
      --run "${nvidiaWrapperScript}/bin/ktalk-nvidia-wrapper \"\$@\""

    # Optional detached launcher (runs in background)
    cat > $out/bin/${pname}-detached <<'EOF'
    #!/usr/bin/env bash
    setsid "${pname}" "$@" >/dev/null 2>&1 &
    disown
    EOF
    chmod +x $out/bin/${pname}-detached

    # Install desktop entry
    mkdir -p $out/share/applications/
    cp ${desktopItem}/share/applications/*.desktop $out/share/applications/

    # Copy icons from extracted AppImage
    if [ -d "${appimageContents}/usr/share/icons" ]; then
      cp -r ${appimageContents}/usr/share/icons/ $out/share/icons/
    fi

    runHook postInstall
  '';
}
