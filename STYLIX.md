# Stylix Theme Management

This configuration uses [Stylix](https://github.com/danth/stylix) for centralized theme, color, and font management across NixOS, nix-darwin, and Home Manager.

## Overview

Stylix provides:
- **Centralized color schemes** using base16 standard
- **Automatic theming** for 100+ applications
- **Consistent fonts** across all programs
- **Wallpaper integration** with color extraction
- **Single configuration** for system-wide aesthetics

## Current Theme: Cyberdream

The default theme is a custom "Cyberdream" dark theme with neon accents:

### Color Palette (Base16)

```nix
base00 = "0f1113"  # Background
base01 = "191d22"  # Surface
base02 = "1f252b"  # Surface variant
base03 = "2b323a"  # Border/comment
base04 = "97a4b6"  # Muted text
base05 = "e6edf3"  # Primary text
base06 = "c1cad6"  # Secondary text
base07 = "ffffff"  # Bright text

base08 = "ff6b82"  # Red
base09 = "ffb86b"  # Orange  
base0A = "ffd76b"  # Yellow
base0B = "78f093"  # Green
base0C = "5ef1ff"  # Cyan
base0D = "5ea1ff"  # Blue
base0E = "bd5eff"  # Purple
base0F = "ff5ef1"  # Magenta
```

### Default Fonts

- **Monospace**: FiraCode Nerd Font (terminal, code)
- **Sans-serif**: CaskaydiaCove Nerd Font (UI, applications)
- **Cursor**: Bibata-Modern-Classic
- **Icons**: Papirus-Dark

## Configuration

### Enabling Stylix

In system configuration (`systems/{arch}/{hostname}/default.nix`):

```nix
# NixOS systems
custom.desktop.stylix = {
  enable = true;
  theme = "cyberdream";
  wallpaper = config.system.wallpaper;  # Use existing wallpaper
};

# Darwin systems  
custom.desktop.stylix = {
  enable = true;
  theme = "cyberdream";
  # No wallpaper on macOS
};
```

### Available Options

All options under `custom.desktop.stylix`:

```nix
{
  # Enable/disable Stylix
  enable = true;  # boolean, default: false

  # Theme selection
  theme = "cyberdream";  # string, default: "cyberdream"
  # Available: "cyberdream", "catppuccin-mocha" (or any base16 scheme)

  # Wallpaper for color extraction
  wallpaper = "/path/to/wallpaper.jpg";  # path or null, default: null

  # Font configuration
  fonts = {
    monospace = {
      package = pkgs.nerd-fonts.fira-code;
      name = "FiraCode Nerd Font";
    };
    sansSerif = {
      package = pkgs.nerd-fonts.caskaydia-cove;
      name = "CaskaydiaCove Nerd Font";
    };
    sizes = {
      terminal = 12;      # Terminal font size
      applications = 11;  # Application font size  
      desktop = 10;       # Desktop/panel font size
    };
  };

  # Cursor theme
  cursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
  };

  # Icon theme
  iconTheme = {
    package = pkgs.papirus-icon-theme;
    name = "Papirus-Dark";
  };
}
```

## Themed Applications

Stylix automatically themes:

### System Level (NixOS/Darwin)
- GTK applications
- GRUB bootloader (if enabled)
- Console/TTY

### Home Manager
- **Terminals**: WezTerm, Kitty, Alacritty, Foot
- **Shells**: Bash, Zsh, Fish
- **Editors**: Neovim, Vim, Helix, Emacs
- **Browsers**: Firefox
- **Tools**: Tmux, Fzf, Btop, Bottom
- **Notifications**: Mako, Dunst
- **Lock screens**: Swaylock
- **Window managers**: Hyprland, Sway, i3
- Many more...

### Custom Theme Overrides

Some applications keep custom themes:

- **Waybar**: Custom Cyberdream CSS theme
- **Rofi**: Custom theme files (cyberdream.rasi, catppuccin-frappe.rasi)
- **Regreet**: Login manager with custom styling

To use Stylix for these instead:
```nix
# In your configuration
stylix.targets.waybar.enable = true;   # Override custom waybar theme
stylix.targets.rofi.enable = true;     # Override custom rofi theme
```

## Changing Themes

### Switch to Catppuccin

```nix
custom.desktop.stylix = {
  enable = true;
  theme = "catppuccin-mocha";  # Change this line
  wallpaper = config.system.wallpaper;
};
```

### Use Any Base16 Theme

Stylix supports 200+ base16 themes from [tinted-theming](https://github.com/tinted-theming/schemes):

```nix
custom.desktop.stylix = {
  enable = true;
  theme = "nord";  # Or: dracula, gruvbox, tokyo-night, etc.
  wallpaper = config.system.wallpaper;
};
```

### Create Custom Theme

Override the base16 scheme directly:

```nix
custom.desktop.stylix = {
  enable = true;
  # Use custom colors instead of predefined theme
  # Set theme to anything other than "cyberdream" 
  # and define manually in the module
};
```

## Wallpaper Integration

Stylix can extract colors from your wallpaper:

```nix
custom.desktop.stylix = {
  enable = true;
  wallpaper = config.system.wallpaper;
  # Stylix will generate base16 scheme from wallpaper
  # Remove 'theme' option to use extracted colors
};
```

## Font Customization

### Change Font Families

```nix
custom.desktop.stylix.fonts = {
  monospace = {
    package = pkgs.nerd-fonts.jetbrains-mono;
    name = "JetBrainsMono Nerd Font";
  };
  sansSerif = {
    package = pkgs.nerd-fonts.hack;
    name = "Hack Nerd Font";
  };
};
```

### Adjust Font Sizes

```nix
custom.desktop.stylix.fonts.sizes = {
  terminal = 14;      # Larger terminal
  applications = 12;  # Larger apps
  desktop = 11;       # Larger panels
};
```

## Per-Application Overrides

Disable Stylix for specific applications:

```nix
# In Home Manager configuration
stylix.targets = {
  waybar.enable = false;      # Keep custom waybar theme
  firefox.enable = false;     # Use default Firefox theme
  neovim.enable = false;      # Keep custom neovim colorscheme
};
```

## Troubleshooting

### Colors Not Applied

1. Check Stylix is enabled: `custom.desktop.stylix.enable = true`
2. Rebuild system: `nixos-rebuild switch` or `darwin-rebuild switch`
3. Restart applications or log out/in

### Font Not Applied

1. Verify font package is installed
2. Check font name matches exactly (use `fc-list` to see available fonts)
3. Some apps need restart to pick up new fonts

### Application-Specific Issues

Some applications may require additional configuration:
- **GTK apps**: Ensure `stylix.targets.gtk.enable = true` (default)
- **Terminal colors**: May require terminal restart
- **Hyprland**: Restart Hyprland session for border colors

## Migration Notes

Previous hardcoded themes removed from:
- ✅ Mako notification daemon
- ✅ Swaylock lock screen  
- ✅ GTK theme configuration
- ✅ Hyprland border colors
- ✅ WezTerm color scheme
- ✅ Font defaults (NixOS)

Custom themes retained for:
- Waybar (custom CSS)
- Rofi (custom .rasi files)
- Regreet login manager

## Resources

- [Stylix Documentation](https://stylix.danth.me)
- [Base16 Schemes](https://github.com/tinted-theming/schemes)
- [Stylix GitHub](https://github.com/danth/stylix)
- Module location: `modules/shared/desktop/stylix/default.nix`

## System Status

### Enabled Systems
- ✅ **nz** (x86_64-linux) - Desktop laptop
- ✅ **porez** (x86_64-linux) - Gaming desktop
- ✅ **mbp16** (aarch64-darwin) - MacBook Pro

### Not Applicable
- ⊘ **beez** - Server (no desktop)
- ⊘ **zanoza** - Server (no desktop)

## Known Issues

### OpenCode Module Conflict

Systems **nz** and **porez** have a pre-existing issue with the opencode module:
```
error: The option `home-manager.users.sab.programs.opencode.themes' does not exist
```

**This is unrelated to Stylix** and needs separate fixing. The opencode package's Home Manager module references a non-existent option.

**Workaround**: Disable opencode temporarily or fix the opencode module.

## Future Enhancements

Potential additions:
- Add Catppuccin theme as named option
- Per-host theme overrides
- Dynamic theme switching based on time of day
- Integration with wallpaper rotation
