{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.suites.develop;
in
{
  options.suites.develop = with types; {
    enable = mkBoolOpt false "Enable the Darwin develop suite";
  };

  config = mkIf cfg.enable {
    custom.tools = {
      lsp.enable = true;
      linters.enable = true;
      k8s.enable = true;
    };
  };
}
