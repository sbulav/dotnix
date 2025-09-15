# DEPRECATED: This module has been replaced by the shared SOPS module
# System-level compatibility layer (SSH key functionality moved to system configs)
{
  config,
  lib,
  namespace,
  ...
}: let
  inherit (lib.${namespace}) mkBoolOpt mkOpt;
  cfg = config.${namespace}.security.sops;
in {
  options.${namespace}.security.sops = with lib.types; {
    enable = mkBoolOpt false "Whether to enable sops.";
    defaultSopsFile = mkOpt path null "Default sops file.";
    sshKeyPaths = mkOpt (listOf path) ["/etc/ssh/ssh_host_ed25519_key"] "SSH Key paths to use.";
    secrets = mkOpt (attrsOf attrs) {} "Secret definitions (handled by system config now).";
  };

  config = lib.mkIf cfg.enable {
    sops = {
      inherit (cfg) defaultSopsFile;
      age = {
        inherit (cfg) sshKeyPaths;
        keyFile = "${config.users.users.${config.${namespace}.user.name}.home}/.config/sops/age/keys.txt";
      };
    } // lib.optionalAttrs (cfg.secrets != {}) {
      secrets = lib.mapAttrs (_: secret: builtins.removeAttrs secret ["uid"]) cfg.secrets;
    };

    warnings = [
      "modules/darwin/system/security/sops is deprecated - use shared SOPS patterns in system configurations"
    ];
  };
}
