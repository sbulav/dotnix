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

  # Constants for paths and settings
  agentDir = ./agent;
  commandDir = ./command;
  toolsDir = ./tools;
  providersPath = ./providers.nix;
  mcpServersPath = ./mcp-servers.nix;
  configSchema = "https://opencode.ai/config.json";

  # Import separate configuration files
  providers = import providersPath;
  mcpServers = import mcpServersPath;

  # Helper function to process config directories
  # dirPath: path to directory containing .nix files
  # Returns: attrset of name -> config for all valid .nix files
  processConfigDir = dirPath: let
    files = builtins.readDir dirPath;
    nixFiles = filterAttrs (name: _: lib.hasSuffix ".nix" name) files;
  in
    lib.mapAttrs' (name: _: let
      filePath = dirPath + "/${name}";
    in
      if builtins.pathExists filePath then
        let
          fileName = lib.removeSuffix ".nix" name;
          config = import filePath;
        in
          nameValuePair fileName config
      else
        # Skip missing files without error
        null) nixFiles;

  # Import configurations from directories
  agents = processConfigDir agentDir;
  commands = processConfigDir commandDir;

  # Process physical tool scripts from tools directory
  physicalTools = let
    files = builtins.readDir toolsDir;
  in
    lib.mapAttrs' (name: _: let
      filePath = toolsDir + "/${name}";
    in
      if builtins.pathExists filePath then
        let
          content = builtins.readFile filePath;
        in
          nameValuePair name content
      else
        null) files;

  # Helper functions to convert Nix to YAML/Markdown

  # Convert optional value to YAML field, skipping null/empty
  # key: string, value: any -> string
  optionalYamlField = key: value:
    if value != null && value != ""
    then "${key}: ${builtins.toJSON value}"
    else "";

  # Convert tools attrset to YAML format
  # tools: attrset of name -> enabled -> string
  toolsToYaml = tools:
    if tools == {} then ""
    else
      let
        toolLines = lib.mapAttrsToList
          (name: enabled: "  ${name}: ${builtins.toJSON enabled}")
          tools;
      in
        "tools:\n" + lib.concatStringsSep "\n" toolLines;

  # Convert permissions attrset to YAML format
  # permission: attrset of name -> value or subattrset -> string
  permissionToYaml = permission:
    if permission == {} then ""
    else
      let
        permLines = lib.mapAttrsToList (name: value:
          if builtins.isAttrs value then
            let
              subLines = lib.mapAttrsToList
                (subName: subValue: "      \"${subName}\": \"${subValue}\"")
                value;
            in
              "  ${name}:\n" + lib.concatStringsSep "\n" subLines
          else
            "  ${name}: \"${value}\""
        ) permission;
      in
        "permission:\n" + lib.concatStringsSep "\n" permLines;

  # Generate common YAML header for markdown
  # config: attrset with description and optional fields -> string
  yamlHeader = config: ''
    ---
    description: ${builtins.toJSON config.description}
  '';

  # Generate agent markdown file
  # name: string, config: attrset -> string
  toMarkdownAgent = name: config: ''
    ${yamlHeader config}
    ${optionalYamlField "mode" (config.mode or null)}
    ${optionalYamlField "model" (config.model or null)}
    ${optionalYamlField "temperature" (config.temperature or null)}
    ${toolsToYaml (config.tools or {})}
    ${permissionToYaml (config.permission or {})}
    ---
    ${config.system_prompt or ""}
  '';

  # Generate command markdown file
  # name: string, config: attrset -> string
  toMarkdownCommand = name: config: ''
    ${yamlHeader config}
    ${optionalYamlField "agent" (config.agent or null)}
    ${optionalYamlField "model" (config.model or null)}
    ---
    ${config.context or ""}

    ${config.task or ""}
  '';

  # Default configuration settings
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

    "$schema" = configSchema;
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

    xdg.configFile = {
      "opencode/opencode.json".text = builtins.toJSON finalSettings;
    }
    # Agent markdown files
    // lib.mapAttrs' (name: value:
        nameValuePair "opencode/agent/${name}.md" {
          text = toMarkdownAgent name value;
        })
      agents
    # Command markdown files
    // lib.mapAttrs' (name: value:
        nameValuePair "opencode/command/${name}.md" {
          text = toMarkdownCommand name value;
        })
      commands
    # Tool scripts (from both options and physical files)
    // lib.mapAttrs' (name: value:
        nameValuePair "opencode/tools/${name}" {
          text = value;
          executable = true;
        })
      (cfg.tools // physicalTools);
  };
}
