{
  options,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.hardware.yubikey;
in
{
  options.hardware.yubikey = with types; {
    enable = mkBoolOpt false "Whether or not to enable yubikey support.";

    smartcard = {
      enable = mkBoolOpt false "Enable YubiKey smartcard (PIV/CCID) mode";
      enablePCSC = mkBoolOpt true "Enable PCSC daemon for smartcard access";
      enableUdevRules = mkBoolOpt true "Add udev rules for YubiKey CCID mode";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Enable U2F authentication
      security.pam.u2f = {
        enable = true;
        # "sufficient" means: if YubiKey is present and valid, auth succeeds immediately
        # If YubiKey is absent or fails, fall through to next auth method (fingerprint/password)
        control = "sufficient";

        settings = {
          # Prompt user to insert YubiKey
          cue = true;
          # Enable debug output (can be disabled after testing)
          debug = false;
          # authpending_file allows proper timeout and fallback to next auth method
          # When YubiKey is not inserted within timeout, authentication falls through to fingerprint
          authpending_file = "/var/run/user/%u/pam-u2f-authpending";
        };
      };

      # Enable U2F for specific PAM services
      security.pam.services = {
        login.u2fAuth = true;
        sudo.u2fAuth = true;
      };

      environment.systemPackages = with pkgs; [
        # Yubico's official tools
        yubikey-manager # cli
        # FIXME: insecure
        # yubikey-manager-qt # gui
        yubikey-personalization # cli
        yubico-piv-tool # cli
        yubioath-flutter # gui
        # reload-yubikey
      ];
    }

    (mkIf cfg.smartcard.enable {
      # Enable PCSC daemon for smartcard access
      services.pcscd = mkIf cfg.smartcard.enablePCSC {
        enable = true;
        plugins = with pkgs; [ ccid ];
      };

      # Add udev rules for YubiKey CCID mode
      services.udev.packages = mkIf cfg.smartcard.enableUdevRules (with pkgs; [
        (writeTextFile {
          name = "yubikey-ccid-rules";
          destination = "/etc/udev/rules.d/70-yubikey-ccid.rules";
          text = ''
            # YubiKey CCID mode rules
            # Allow all users to access YubiKey in CCID mode
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0407", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0401", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0402", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0403", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0404", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0405", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0406", MODE="0666", GROUP="users"
            
            # YubiKey 5 series
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0407", MODE="0666", GROUP="users"
            
            # YubiKey NEO
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0111", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0112", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0113", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0114", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0115", MODE="0666", GROUP="users"
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="0116", MODE="0666", GROUP="users"
          '';
        })
      ]);

      # Add smartcard-specific packages
      environment.systemPackages = with pkgs; [
        pcsc-tools
        gnupg-pkcs11-scd
      ];
    })
  ]);
}