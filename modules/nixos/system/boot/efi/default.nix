{
  options,
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.boot.efi;
in
{
  options.system.boot.efi = with types; {
    enable = mkBoolOpt false "Whether or not to enable efi booting.";
    quiet = mkBoolOpt false "Quiet one-second boot: short menu timeout, no kernel chatter on the console.";
  };

  config = mkIf cfg.enable {
    boot.loader.systemd-boot.enable = true;
    boot.kernelParams = [
      "ipv6.disable=1"
    ]
    ++ optionals cfg.quiet [
      "quiet"
      "udev.log_level=3"
    ];
    boot.loader.systemd-boot.configurationLimit = 5;
    boot.loader.efi.canTouchEfiVariables = true;

    # Hold Space in the menu (or pick an older generation) still works;
    # the log stays in journalctl -b.
    boot.loader.timeout = mkIf cfg.quiet (mkDefault 1);
    boot.consoleLogLevel = mkIf cfg.quiet (mkDefault 3);
    boot.initrd.verbose = mkIf cfg.quiet (mkDefault false);

    # https://github.com/NixOS/nixpkgs/blob/c32c39d6f3b1fe6514598fa40ad2cf9ce22c3fb7/nixos/modules/system/boot/loader/systemd-boot/systemd-boot.nix#L66
    # boot.loader.systemd-boot.editor = false;
  };
}
