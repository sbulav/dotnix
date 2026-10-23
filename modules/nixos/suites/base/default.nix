{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.suites.base;
in
{
  options.suites.base = {
    enable = mkBoolOpt false "Whether to enable the base suite shared by the common and server suites";
  };

  config = mkIf cfg.enable {
    system = {
      nix.enable = true;

      locale.enable = true;
      time.enable = true;

      memory.enable = true;
      journald.enable = true;
      network-tuning.enable = true;

      security.sudo.enable = true;
      security.gpg.enable = true;
    };

    hardware.storage.enable = true;

    services.ssh.enable = true;
    services.irqbalance.enable = true;

    custom.tools = {
      http.enable = true;
      misc.enable = true;
      net.enable = true;
    };
    custom.cli-apps.neovim.enable = mkDefault true;
  };
}
