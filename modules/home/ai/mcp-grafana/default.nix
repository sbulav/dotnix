{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.ai.mcp-grafana;
in
{
  options.custom.ai.mcp-grafana = {
    enable = mkEnableOption "Enable MCP server for Grafana integration";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      mcp-grafana
    ];

    # Define SOPS secret for Grafana API key
    sops.secrets.grafana_api_key = {
      sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
    };
    # Define SOPS secret for Grafana API key
    sops.secrets.grafana_host = {
      sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
    };
  };
}
