#!/usr/bin/env bash
# Test script for ktalk-nvidia package

set -e

echo "=== Testing ktalk-nvidia package ==="
echo ""

# Check if we can run the wrapper
echo "1. Checking wrapper script..."
if [ -f ./result/bin/ktalk-nvidia ]; then
    echo "✓ Wrapper script found at ./result/bin/ktalk-nvidia"
    
    # Check wrapper content
    echo ""
    echo "2. Checking wrapper environment variables..."
    grep -E "export|EGL|LD_LIBRARY_PATH|CHROMIUM" ./result/bin/ktalk-nvidia | head -10
    
    # Check desktop file
    echo ""
    echo "3. Checking desktop file..."
    if [ -f ./result/share/applications/ktalk-nvidia.desktop ]; then
        echo "✓ Desktop file found"
        cat ./result/share/applications/ktalk-nvidia.desktop
    else
        echo "✗ Desktop file not found"
    fi
    
    # Check extracted AppImage
    echo ""
    echo "4. Checking extracted AppImage..."
    extracted_path=$(grep "exec \"" ./result/bin/ktalk-nvidia | cut -d'"' -f2 | cut -d'"' -f1)
    if [ -f "$extracted_path" ]; then
        echo "✓ Extracted AppImage found at: $extracted_path"
        echo "  File size: $(ls -lh "$extracted_path" | awk '{print $5}')"
    else
        echo "✗ Extracted AppImage not found"
    fi
    
    echo ""
    echo "=== Package structure looks good ==="
    echo ""
    echo "To install in your NixOS configuration:"
    echo "1. Add to configuration.nix:"
    echo "   environment.systemPackages = with pkgs; ["
    echo "     (callPackage /home/sab/dotnix/packages/ktalk-nvidia/package.nix {})"
    echo "   ];"
    echo ""
    echo "2. Or use with home-manager:"
    echo "   home.packages = with pkgs; ["
    echo "     (callPackage /home/sab/dotnix/packages/ktalk-nvidia/package.nix {})"
    echo "   ];"
    echo ""
    echo "The application will appear as 'Толк (NVIDIA)' in your application menu."
    
else
    echo "✗ Package not built. Run: nix-build test-build.nix"
    exit 1
fi