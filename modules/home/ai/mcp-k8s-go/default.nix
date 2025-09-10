{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.ai.mcp-k8s-go;
in {
  options.custom.ai.mcp-k8s-go = {
    enable = mkEnableOption "Enable MCP server connecting to Kubernetes";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      mcp-k8s-go
    ];
  };
}
