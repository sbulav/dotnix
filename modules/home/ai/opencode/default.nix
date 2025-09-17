{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    mapAttrs'
    nameValuePair
    filterAttrs
    ;

  cfg = config.custom.ai.opencode;

  # Import separate configuration files
  providers = import ./providers.nix;
  mcpServers = import ./mcp-servers.nix;

  # Import agent configurations from agent/ directory
  agentFiles = builtins.readDir ./agent;
  agents = lib.mapAttrs' (name: _: let
    fileName = lib.removeSuffix ".nix" name;
    agentConfig = import (./agent + "/${name}");
  in
    nameValuePair fileName agentConfig) (filterAttrs (name: _: lib.hasSuffix ".nix" name) agentFiles);

  # Import command configurations from command/ directory
  commandFiles = builtins.readDir ./command;
  commands = lib.mapAttrs' (name: _: let
    fileName = lib.removeSuffix ".nix" name;
    commandConfig = import (./command + "/${name}");
  in
    nameValuePair fileName commandConfig) (filterAttrs (name: _: lib.hasSuffix ".nix" name) commandFiles);

   # Helper functions to convert Nix to YAML/Markdown
   optionalToYaml = key: value:
     if value != null && value != ""
     then "${key}: ${builtins.toJSON value}"
     else "";

   toolsToYaml = tools:
     if tools == {} then "" else
     let
       toolLines = lib.mapAttrsToList (name: enabled: "  ${name}: ${builtins.toJSON enabled}") tools;
     in
     "tools:\n" + lib.concatStringsSep "\n" toolLines;

   permissionToYaml = permission:
     if permission == {} then "" else
     let
       permLines = lib.mapAttrsToList (name: value:
         if builtins.isAttrs value then
           let
             subLines = lib.mapAttrsToList (subName: subValue:
               "      \"${subName}\": \"${subValue}\""
             ) value;
           in
           "  ${name}:\n" + lib.concatStringsSep "\n" subLines
         else
           "  ${name}: \"${value}\""
       ) permission;
     in
     "permission:\n" + lib.concatStringsSep "\n" permLines;

   toMarkdownAgent = name: config: ''
     ---
     description: ${builtins.toJSON config.description}
     ${optionalToYaml "mode" (config.mode or null)}
     ${optionalToYaml "model" (config.model or null)}
     ${optionalToYaml "temperature" (config.temperature or null)}
     ${toolsToYaml (config.tools or {})}
     ${permissionToYaml (config.permission or {})}
     ---
     ${config.system_prompt or ""}
   '';

   toMarkdownCommand = name: config: ''
     ---
     description: ${builtins.toJSON config.description}
     ${optionalToYaml "agent" (config.agent or null)}
     ${optionalToYaml "model" (config.model or null)}
     ---
     ${config.context or ""}

     ${config.task or ""}
   '';

   # Merge all configurations into settings
   defaultSettings = {
     model = "hhdev-openai/gpt-4.1";
     small_model = "hhdev-openai/gpt-4.1";

     disabled_providers = [
       "openai"
       "amazon-bedrock"
       "opencode"
     ];

     provider = providers;
     mcp = mcpServers;

     "$schema" = "https://opencode.ai/config.json";
   };

   # Final settings with user overrides
   finalSettings = lib.recursiveUpdate defaultSettings cfg.settings;
in {
  options.custom.ai.opencode = {
    enable = mkEnableOption "Enable opencode AI assistant";

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Configuration for opencode.json";
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
        "opencode/opencode.json".text = builtins.toJSON finalSettings;
      }
      // mapAttrs' (
        name: value:
          nameValuePair "opencode/agent/${name}.md" {text = toMarkdownAgent name value;}
      )
      agents
      // mapAttrs' (
        name: value:
          nameValuePair "opencode/command/${name}.md" {text = toMarkdownCommand name value;}
      )
      commands
      // mapAttrs' (
        name: value:
          nameValuePair "opencode/tools/${name}" {
            text = value;
            executable = true;
          }
      )
      cfg.tools;
  };
}
