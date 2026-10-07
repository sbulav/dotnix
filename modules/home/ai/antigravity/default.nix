{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.ai.antigravity;
  proxy = import ../shared/proxy.nix;

  # The agy binary is a locally built, pinned vendor binary outside the
  # store; nix-ld on the host supplies its loader. This wrapper shadows it on
  # PATH (the HM profile precedes /usr/local/bin) to pin the proxy topology,
  # the same contract as the claude and opencode wrappers. agy self-updates
  # on startup whenever its directory is writable and swaps the binary in
  # place; the env switch only accepts `true` (`1` is ignored).
  agy = pkgs.writeShellScriptBin "agy" (
    optionalString pkgs.stdenv.isLinux ''
      export HTTPS_PROXY='${proxy.httpProxy}' HTTP_PROXY='${proxy.httpProxy}'
      export NO_PROXY='${proxy.noProxy}'
    ''
    + ''
      export AGY_CLI_DISABLE_AUTO_UPDATE=true
      exec '${cfg.binary}' "$@"
    ''
  );
in
{
  options.custom.ai.antigravity = {
    enable = mkBoolOpt false "Whether to wrap the vendor-installed Antigravity CLI (agy) with the corporate proxy";
    binary = mkOpt types.str "/usr/local/bin/agy" "Path to the vendor-installed agy binary";
  };

  config = mkIf cfg.enable {
    home.packages = [ agy ];
  };
}
