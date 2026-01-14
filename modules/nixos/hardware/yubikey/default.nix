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
      enable = mkBoolOpt false "Whether to enable YubiKey smartcard/GPG support.";
    };
  };

  config = mkIf cfg.enable {
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
    ] ++ optionals cfg.smartcard.enable [
      # Smartcard/GPG tools
      gnupg
      pcsc-tools
    ];

    # Smartcard-specific configuration
    services = mkIf cfg.smartcard.enable {
      # Add YubiKey udev rules for smartcard access
      udev.packages = with pkgs; [ yubikey-personalization ];

      # Enable pcscd for compatibility with other smartcards
      # Note: YubiKey works fine with GPG's internal CCID driver,
      # but pcscd is useful for pcsc-tool debugging
      pcscd = {
        enable = true;
        plugins = with pkgs; [ ccid ];
      };
    };

    # Configure GPG agent for YubiKey smartcard support
    programs.gnupg.agent = mkIf cfg.smartcard.enable {
      enable = true;
      enableSSHSupport = true;
    };

    # Create scdaemon configuration for YubiKey
    # YubiKey works best with GPG's internal CCID driver (default behavior)
    # We don't need special configuration - GPG will auto-detect the YubiKey
    environment.etc."scdaemon.conf" = mkIf cfg.smartcard.enable {
      text = ''
        # YubiKey works with internal CCID driver (do NOT disable-ccid)
        # GPG's internal driver has better YubiKey support than pcscd
        
        # Optional: Enable debug logging if needed
        # log-file /tmp/scdaemon.log
        # debug-level basic
        
        # Optional: Specify card timeout (default is fine for YubiKey)
        # card-timeout 5
      '';
    };
  };
}
