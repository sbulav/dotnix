# ktalk-nvidia

Nix package for Kontur.Talk (Толк) with NVIDIA GPU support for virtual backgrounds.

## Problem Solved

The official Ktalk AppImage shows a white screen for virtual background/blur effects on NVIDIA GPUs with Wayland/Hyprland. This package fixes:

- `eglGetProcAddress not found` errors in GPU process
- EGL library loading issues on NVIDIA
- Virtual background white screen
- GPU process initialization failures

## Installation

### Option 1: Add to NixOS configuration

Add to your `/etc/nixos/configuration.nix`:

```nix
{ pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    (callPackage /path/to/ktalk-nvidia/package.nix {})
  ];
}
```

### Option 2: Use with home-manager

Add to your home-manager configuration:

```nix
{ pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    (callPackage /path/to/ktalk-nvidia/package.nix {})
  ];
}
```

### Option 3: Build and run directly

```bash
cd /home/sab/dotnix/packages/ktalk-nvidia
NIXPKGS_ALLOW_UNFREE=1 nix-build test-build.nix
./result/bin/ktalk-nvidia
```

## What This Package Does

1. **Downloads the official AppImage** from Ktalk servers
2. **Extracts the AppImage** using Nix's appimageTools
3. **Creates a wrapper script** that sets up NVIDIA environment:
   - Sets EGL vendor to NVIDIA
   - Adds NVIDIA libraries to LD_LIBRARY_PATH
   - Configures EGL platform for Wayland/X11
   - Sets Chromium flags for GPU acceleration
4. **Creates a desktop entry** named "Толк (NVIDIA)"

## Technical Details

The wrapper script sets these critical environment variables:

```bash
# EGL vendor configuration
export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json

# NVIDIA libraries
export LD_LIBRARY_PATH="/nix/store/...-nvidia-x11-.../lib:$LD_LIBRARY_PATH"

# Session-specific settings
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
  export EGL_PLATFORM=wayland
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
else
  export EGL_PLATFORM=x11
fi

# GPU acceleration flags
export CHROMIUM_FLAGS="--use-gl=egl --enable-features=Vulkan --ignore-gpu-blocklist --disable-gpu-driver-bug-workarounds --enable-webgl --enable-webgl2-compute-context --enable-accelerated-2d-canvas"
```

## Testing

After installation, verify virtual background works:

1. Launch "Толк (NVIDIA)" from application menu
2. Start a video call
3. Click the background effects button (blur or virtual background)
4. The effect should work without white screen

## Files

- `package.nix` - Main package definition
- `test-build.nix` - Test build file
- `flake.nix` - Flake for modern Nix
- `test-run.sh` - Test script
- `README.md` - This file

## License

This package is for the proprietary Kontur.Talk application. The wrapper and packaging code is MIT licensed, but the actual application remains proprietary.