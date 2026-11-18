# Only profile quality choices are Nix-owned here. Language policy remains
# independent, and existing media/downloads are never searched or removed.
{
  app,
  port,
  configXml,
}:
{ pkgs, lib, ... }:
let
  policy = pkgs.writeShellApplication {
    name = "${app}-quality-policy";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./apply-arr-quality-policy.py} \
        --url http://127.0.0.1:${toString port}/api/v3 \
        --config-xml ${lib.escapeShellArg configXml} \
        --backup ${lib.escapeShellArg "${builtins.dirOf configXml}/quality-policy-backup.json"}
    '';
  };
in
{
  systemd.services."${app}-quality-policy" = {
    description = "Require clean HD/UHD sources and prefer UHD in ${app}";
    wantedBy = [ "multi-user.target" ];
    after = [ "${app}.service" ] ++ lib.optional (app == "sonarr") "sonarr-language-policy.service";
    wants = [ "${app}.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe policy;
      TimeoutStartSec = 600;
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
  systemd.timers."${app}-quality-policy" = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnUnitActiveSec = "5min";
  };
}
