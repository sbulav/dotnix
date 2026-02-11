{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
with lib.custom;
let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.stdenv.hostPlatform.system}.full;
in
{
  custom = {
    user = {
      enable = true;
      name = config.snowfallorg.user.name;
    };

    desktop = {
      hyprland = {
        enable = true;
        # Auto-detect monitors initially - update with actual port names after NVIDIA drivers load
        # Run 'hyprctl monitors' to see actual port names (e.g., DP-1, DP-2, HDMI-A-1)
        # Previous Intel Arc config: HDMI-A-1,1920x1080,0x0,1 and DP-2,3840x2560@60,1920x0,2
        monitors = [
          # ",preferred,auto,auto"
          "HDMI-A-1,1920x1080,0x0,1"
          "DP-1,3840x2560@60,1920x0,2"
          ",preferred,auto,auto"
        ];
        workspaces.monitorBindings = {
          "1" = "DP-1";
          "2" = "DP-1";
          "3" = "DP-1";
          "4" = "DP-1";
          "5" = "DP-1";
          "6" = "DP-1";
          "7" = "HDMI-A-1";
          "8" = "HDMI-A-1";
          "9" = "HDMI-A-1";
        };
        keybindings = {
          copy = "C";
          paste = "V";
          clipboard = "SHIFT C";
        };
      };
      addons = {
        hyprpaper = enabled;
        mako = enabled;
        rofi = enabled;
        kitty = disabled;
        swaylock = enabled;
        hypridle = {
          enable = true;
          profile = "pc";
        };
        waybar = {
          enable = true;
          keyboardName = "kinesis-advantage2-keyboard-1";
          temperature = {
            enable = true;

            # AMD Ryzen k10temp sensor - use hwmon0 which corresponds to k10temp-pci-00c3
            hwmonPath = "/sys/class/hwmon/hwmon4/temp1_input";
            criticalThreshold = 85;
            tooltip = true;
          };
        };
        wlogout = enabled;
        hyprlock = disabled;
        wezterm = enabled;
        "wlr-which-key" = enabled;
        wallpaper = "${wallpapers}/share/wallpapers/cities/1-osaka-jade-bg.jpg";

        waypaper = {
          enable = true;
          wallpaperDirectory = "${wallpapers}/share/wallpapers";
        };
      };
    };

    ai = {
      opencode = enabled;
      mcp-k8s-go = enabled;
    };

    apps = {
      obsidian = enabled;
      ktalk = {
        enable = true;
        package = pkgs.custom.ktalk-nvidia;
      };
      libreoffice = enabled;
    };

    cli-apps = {
      argocd = enabled;
      atuin = enabled;
      bottom = enabled;
      fastfetch = enabled;
      home-manager = enabled;
      yazi = enabled;
    };
    tools = {
      direnv = disabled;
      gh = disabled;
      git = {
        enable = true;
        enableSigning = true;
        gpgProgram = "${pkgs.custom.gpg-smart-sign}/bin/gpg-smart-sign";
        signingKey = "15DB4B4A58D027CB73D0E911D06334BAEC6DC034"; # YubiKey key (fallback: 7C43420F61CEC7FB)
      };
      k9s = enabled;
      opentofu = enabled;
      tea = enabled;
      sqlite-jira = enabled;
      yandex-cloud = disabled;
    };
    security = {
      gpg = {
        enable = true;
        agentTimeout = 5;
        yubikeyKeyId = ""; # Auto-detect from YubiKey card
        fallbackKeyId = "7C43420F61CEC7FB";
      };
      rbw = enabled;
      vault = enabled;
      openconnect = enabled;
      sops = {
        enable = true;
        # Shared module auto-resolves to secrets/sab/default.yaml
        commonSecrets.enableCredentials = true;
        profile = "home";
      };
    };
  };

  # env_credentials now handled by commonSecrets.enableCredentials = true
  home.stateVersion = "25.11";
}
