{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.ai.usage;
  proxy = import ../shared/proxy.nix;
  # The collector itself keeps fwdproxy (it only talks to api.anthropic.com).
  # The codex app-server child it spawns must not: fwdproxy stalls CONNECT
  # chatgpt.com and direct chatgpt.com is Cloudflare-challenged since
  # 2026-09-02, so probe_codex pins the child to the homelab VLESS exits via
  # AI_USAGE_CODEX_PROXY (see proxy.nix) while this parent env stays intact.

  # Single source of truth for the cache location: the wrapper env covers the
  # collector (service-spawned or manual), the substitution covers the reader.
  stateFile = "${config.xdg.stateHome}/sab/ai-usage/state.json";

  collector = pkgs.symlinkJoin {
    name = "ai-usage-proxied";
    paths = [ pkgs.custom.ai-usage ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/ai-usage-update \
        --set AI_USAGE_STATE_FILE '${stateFile}' \
        --set AI_USAGE_CODEX_BIN '${lib.getExe pkgs.unstable.codex}' \
        --set AI_USAGE_CODEX_PROXY '${proxy.vlessProxy}' \
        --set HTTP_PROXY '${proxy.httpProxy}' \
        --set HTTPS_PROXY '${proxy.httpProxy}' \
        --set http_proxy '${proxy.httpProxy}' \
        --set https_proxy '${proxy.httpProxy}' \
        --set NO_PROXY '${proxy.noProxy}' \
        --set no_proxy '${proxy.noProxy}'
    '';
  };

  pluginSource = pkgs.runCommand "noctalia-ai-usage-plugin" { } ''
    mkdir -p $out/ai_usage
    cp -r ${./plugin}/. $out/ai_usage/
    chmod -R u+w $out/ai_usage
    substituteInPlace $out/ai_usage/plugin.toml \
      --replace-fail '@NOCTALIA@' '${config.programs.noctalia.package}/bin/noctalia'
    substituteInPlace $out/ai_usage/service.luau \
      --replace-fail '@AI_USAGE_UPDATE@' '${collector}/bin/ai-usage-update' \
      --replace-fail '@STATE_FILE@' '${stateFile}'
    substituteInPlace $out/ai_usage/panel.luau \
      --replace-fail '@NOCTALIA@' '${config.programs.noctalia.package}/bin/noctalia'
  '';
in
{
  options.custom.ai.usage = {
    enable = mkBoolOpt false "Whether to show live Claude Code and Codex subscription limits in Noctalia.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isLinux;
        message = "custom.ai.usage currently requires Linux and Noctalia.";
      }
      {
        assertion = config.custom.desktop.addons.noctalia.enable;
        message = "custom.ai.usage requires custom.desktop.addons.noctalia.enable.";
      }
    ];

    home.packages = [ collector ];

    programs.noctalia.settings = {
      widget.ai-usage.type = "sab/ai_usage:status";
      plugins = {
        enabled = mkAfter [ "sab/ai_usage" ];
        source = mkAfter [
          {
            name = "ai-usage";
            kind = "path";
            location = "${pluginSource}";
            enabled = true;
          }
        ];
      };
    };
  };
}
