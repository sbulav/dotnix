{ pkgs, lib, ... }:
let
  pname = "ktalk-nvidia";
  version = "3.3.0";

  # Download original AppImage
  src = builtins.fetchurl {
    url = "https://st.ktalk.host/ktalk-app/linux/ktalk${version}x86_64.AppImage";
    sha256 = "1lmqpx6kg6ih49jfs5y0nmac7n8xix9ax45ca1bx96cdbwzfryyn";
  };

  # Extract the AppImage
  extracted = pkgs.appimageTools.extractType2 {
    inherit pname version src;
  };

  # NVIDIA-specific desktop item
  desktopItem = pkgs.makeDesktopItem {
    name = "ktalk-nvidia";
    desktopName = "Толк (NVIDIA)";
    comment = "Kontur.Talk with NVIDIA GPU support";
    icon = "ktalk";
    exec = "ktalk-nvidia %U";
    categories = [ "VideoConference" "AudioVideo" "Audio" "Video" "Network" ];
    mimeTypes = [ "x-scheme-handler/ktalk" ];
  };

  # Create wrapper script
  wrapperScript = pkgs.writeShellScript "ktalk-nvidia-wrapper" ''
    #!/usr/bin/env bash
    # ktalk-nvidia wrapper with NVIDIA GPU support

    # Set EGL vendor to NVIDIA
    export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json

    # Add system NVIDIA libraries to library path
    export LD_LIBRARY_PATH="${pkgs.linuxPackages.nvidia_x11}/lib:$LD_LIBRARY_PATH"

    # Set EGL platform based on current session
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
      export EGL_PLATFORM=wayland
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
    else
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
    echo "========================================="
    echo ""
    echo "Starting Ktalk with fixed GPU configuration..."
    echo "Virtual background should now work correctly."
    echo ""

    # Run the extracted AppImage
    exec "${extracted}/AppRun" "$@"
  '';

in
pkgs.stdenv.mkDerivation rec {
  inherit pname version;

  nativeBuildInputs = with pkgs; [
    makeWrapper
  ];

  buildInputs = with pkgs; [
    linuxPackages.nvidia_x11
  ];

  dontUnpack = true;

  installPhase = ''
    echo "=== Installing ktalk-nvidia ==="
    
    # Create output directories
    mkdir -p $out/bin
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor
    
    # Install wrapper script
    cp ${wrapperScript} $out/bin/ktalk-nvidia
    chmod +x $out/bin/ktalk-nvidia
    
    # Install desktop file
    cp ${desktopItem}/share/applications/*.desktop $out/share/applications/
    
    # Copy icons from extracted AppImage
    echo "Copying icons..."
    if [ -d "${extracted}/usr/share/icons" ]; then
      cp -r "${extracted}/usr/share/icons"/* $out/share/icons/ 2>/dev/null || true
    fi
    
    # Also look for icons in the extracted directory
    find "${extracted}" -name "*.png" -o -name "*.svg" | head -10 | while read icon; do
      icon_name=$(basename "$icon")
      if [[ "$icon_name" =~ ktalk|Ktalk|KTALK ]]; then
        icon_size=$(echo "$icon" | grep -oE "[0-9]+x[0-9]+" || echo "scalable")
        mkdir -p "$out/share/icons/hicolor/$icon_size/apps"
        cp "$icon" "$out/share/icons/hicolor/$icon_size/apps/ktalk.png" 2>/dev/null || true
      fi
    done
    
    echo "=== Installation complete ==="
  '';

  meta = with lib; {
    description = "Kontur.Talk with NVIDIA GPU support for virtual backgrounds";
    longDescription = ''
      A space for communication and teamwork with fixed NVIDIA GPU support.
      
      This version includes fixes for:
      - Virtual background/blur effects on NVIDIA GPUs
      - EGL library compatibility issues on Wayland
      - GPU process initialization failures
      
      It combines hangouts, chat rooms, webinars, online whiteboards and an
      application for meeting rooms. Allows you to capture and save the result of
      communications.
    '';
    homepage = "https://kontur.ru/talk";
    license = licenses.unfree;
    maintainers = with maintainers; [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ktalk-nvidia";
  };
}