{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
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
  pluginDir = ./plugin;
  utilsDir = ./utils;
  providersPath = ./providers.nix;
  configSchema = "https://opencode.ai/config.json";

  proxy = import ../shared/proxy.nix;
  registry = import ../shared/registry.nix { inherit lib; };

  # On Linux bake the proxy topology into the binary (same as the Claude
  # wrapper): openai/* API traffic goes via fwdproxy, the LLM gateways
  # (llmgtw.hhdev.ru, llm-gateway.pyn.ru) match NO_PROXY and go direct. --set
  # overrides whatever env a parent process (e.g. a Claude session dispatching
  # `opencode run` workers) passes down, so subagents always route correctly.
  opencodeWrapped =
    if pkgs.stdenv.isLinux then
      pkgs.symlinkJoin {
        name = "opencode";
        paths = [ pkgs.unstable.opencode ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/opencode \
            --set HTTPS_PROXY "${proxy.httpProxy}" \
            --set HTTP_PROXY  "${proxy.httpProxy}" \
            --set NO_PROXY    "${proxy.noProxy}"
        '';
      }
    else
      pkgs.unstable.opencode;

  # Shell used by the bash tool (and TUI terminal). The proxy env above is for
  # the opencode process's API traffic only — shell commands (kubectl, nix,
  # tea, git) must run direct, so strip the vars before handing over to the
  # user's shell. A command can still opt back in with an inline
  # `HTTPS_PROXY=... cmd` since the unset happens at shell startup.
  proxyFreeShell = pkgs.writeShellScript "opencode-shell" ''
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy
    exec "''${SHELL:-${pkgs.bash}/bin/bash}" "$@"
  '';

  # Import separate configuration files
  providers = import providersPath;

  # Helper function to process config directories
  # dirPath: path to directory containing .nix files
  # Returns: attrset of name -> config for all valid .nix files
  processConfigDir =
    dirPath:
    let
      files = builtins.readDir dirPath;
      nixFiles = filterAttrs (name: _: lib.hasSuffix ".nix" name) files;
    in
    lib.mapAttrs' (
      name: _:
      let
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
        null
    ) nixFiles;

  # Import configurations from directories
  agents = processConfigDir agentDir;
  commands = processConfigDir commandDir;
  skills = registry.skills;
  plugins = processConfigDir pluginDir;

  # Process physical utility scripts from utils directory
  physicalUtils =
    if builtins.pathExists utilsDir then
      let
        files = builtins.readDir utilsDir;
      in
      lib.mapAttrs' (
        name: _:
        let
          filePath = utilsDir + "/${name}";
        in
        if builtins.pathExists filePath then
          let
            content = builtins.readFile filePath;
          in
          nameValuePair name content
        else
          null
      ) files
    else
      { };

  # Helper functions to convert Nix to YAML/Markdown

  # Convert optional value to YAML field, skipping null/empty
  # key: string, value: any -> string
  optionalYamlField =
    key: value: if value != null && value != "" then "${key}: ${builtins.toJSON value}" else "";

  # Convert tools attrset to YAML format
  # tools: attrset of name -> enabled -> string
  toolsToYaml =
    tools:
    if tools == { } then
      ""
    else
      let
        toolLines = lib.mapAttrsToList (name: enabled: "  ${name}: ${builtins.toJSON enabled}") tools;
      in
      "tools:\n" + lib.concatStringsSep "\n" toolLines;

  # Convert permissions attrset to YAML format
  # permission: attrset of name -> value or subattrset -> string
  permissionToYaml =
    permission:
    if permission == { } then
      ""
    else
      let
        permLines = lib.mapAttrsToList (
          name: value:
          if builtins.isAttrs value then
            let
              subLines = lib.mapAttrsToList (subName: subValue: "      \"${subName}\": \"${subValue}\"") value;
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
    ${toolsToYaml (config.tools or { })}
    ${permissionToYaml (config.permission or { })}
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
    ${config.requirements or config.context or ""}
    ${config.task or ""}
  '';

  # Default configuration settings
  defaultSettings = {
    model = "hhdev-glm5-fp8/zai-org/GLM-5.2-FP8";
    # Titles and summaries are pure text work: hand them to the fastest free
    # self-hosted model instead of occupying GLM.
    small_model = "hhdev-gemma4-26b/google/gemma-4-26B-A4B-it";

    permission = registry.permissions.opencode;

    disabled_providers = [
      # "openai"
      "amazon-bedrock"
      # "opencode"
    ];

    provider = providers;
    mcp = registry.mcp.opencode;

    "$schema" = configSchema;
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    shell = "${proxyFreeShell}";
  };

  # Final settings with user overrides
  finalSettings = lib.recursiveUpdate defaultSettings cfg.settings;
in
{
  options.custom.ai.opencode = {
    enable = mkEnableOption "Enable opencode AI assistant";

    settings = mkOption {
      type = types.attrs;
      default = { };
      description = "Configuration for opencode.json";
    };

    utils = mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = "Utility scripts placed in the utils directory";
    };

    plugins = mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = "Plugin JS files to generate (merged with plugin/ directory)";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      opencodeWrapped
    ];

    xdg.configFile = {
      "opencode/opencode.json".text = builtins.toJSON finalSettings;
    }
    # Agent markdown files
    // lib.mapAttrs' (
      name: value:
      nameValuePair "opencode/agents/${name}.md" {
        text = toMarkdownAgent name value;
      }
    ) agents
    # Command markdown files
    // lib.mapAttrs' (
      name: value:
      nameValuePair "opencode/commands/${name}.md" {
        text = toMarkdownCommand name value;
      }
    ) commands
    # Skill markdown files (placed in skills/<name>/SKILL.md)
    // lib.mapAttrs' (
      name: value:
      nameValuePair "opencode/skills/${value.name}/SKILL.md" {
        text = registry.toSkillMarkdown name value;
      }
    ) skills
    # Utility scripts (from both options and physical files)
    // lib.mapAttrs' (
      name: value:
      nameValuePair "opencode/utils/${name}" {
        text = value;
        executable = true;
      }
    ) (cfg.utils // physicalUtils)
    # Plugin JS files (from both options and physical files)
    // lib.mapAttrs' (
      name: value:
      nameValuePair "opencode/plugins/${name}.js" {
        text = value;
      }
    ) (cfg.plugins // plugins);
  };
}
