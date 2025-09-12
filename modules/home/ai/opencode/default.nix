{
  lib,
  config,
  pkgs,
  namespace,
  ...
}: let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    mapAttrs'
    nameValuePair;

  cfg = config.custom.ai.opencode;
in {
  options.custom.ai.opencode = {
    enable = mkEnableOption "Enable opencode AI assistent";
    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Configuration for opencode.json";
    };
    agents = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = "Agent configuration files";
    };
    commands = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = "Command configuration files";
    };
    tools = mkOption {
      type = types.attrsOf types.lines;
      default = {};
      description = "Tool scripts placed in the tools directory";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      opencode
    ];
    xdg.configFile =
      {
        "opencode/opencode.json".text = builtins.toJSON cfg.settings;
      }
      // mapAttrs' (name: value:
        nameValuePair "opencode/agents/${name}.json" {text = builtins.toJSON value;}
      ) cfg.agents
      // mapAttrs' (name: value:
        nameValuePair "opencode/commands/${name}.json" {text = builtins.toJSON value;}
      ) cfg.commands
      // mapAttrs' (name: value:
        nameValuePair "opencode/tools/${name}" {
          text = value;
          executable = true;
        }
      ) cfg.tools;
  };
}
