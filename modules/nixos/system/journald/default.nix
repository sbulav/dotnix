{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.journald;
in
{
  options.system.journald = with types; {
    enable = mkBoolOpt false "Whether to enable journald size and retention limits";
    systemMaxUse = mkOpt str "200M" "Maximum disk space the persistent journal may use";
    systemMaxFileSize = mkOpt str "100M" "Maximum size of an individual journal file";
    runtimeMaxUse = mkOpt str "100M" "Maximum space the volatile (runtime) journal may use";
    maxRetentionSec = mkOpt str "1month" "Maximum age of journal entries";
  };

  config = mkIf cfg.enable {
    services.journald.extraConfig = ''
      SystemMaxUse=${cfg.systemMaxUse}
      SystemMaxFileSize=${cfg.systemMaxFileSize}
      RuntimeMaxUse=${cfg.runtimeMaxUse}
      MaxRetentionSec=${cfg.maxRetentionSec}
    '';
  };
}
