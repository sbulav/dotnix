# fj-ex: Forgejo Actions CLI (job logs, rerun, cancel, wait).
#
# fj (forgejo-cli) covers issues and pull requests but only lists Actions
# tasks; fj-ex adds job logs, rerun, cancel and wait.
#
# The wrapper reads the sops-managed token (secrets/sab, key forgejo_token) at
# call time, so it never lands in the Nix store or in the shell/agent
# environment — it exists only inside the fj-ex process. fj-ex sends an env
# token to whichever host a command targets, so keep the token scoped to this
# wrapper; do not export FORGEJO_TOKEN session-wide.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf types;
  inherit (lib.custom) mkOpt;

  cfg = config.custom.tools.fj-ex;

  wrapper = pkgs.writeShellScriptBin "fj-ex" ''
    token_file=${config.sops.secrets.forgejo_token.path}
    if [ -z "''${FJ_EX_TOKEN:-}" ] && [ -z "''${FORGEJO_TOKEN:-}" ] && [ -r "$token_file" ]; then
      FORGEJO_TOKEN="$(${pkgs.coreutils}/bin/cat "$token_file")"
      export FORGEJO_TOKEN
    fi
    export FJ_FALLBACK_HOST="''${FJ_FALLBACK_HOST:-${cfg.host}}"
    exec ${lib.getExe pkgs.custom.fj-ex} "$@"
  '';
in
{
  options.custom.tools.fj-ex = {
    enable = mkEnableOption "fj-ex (Forgejo Actions CLI: logs, rerun, cancel, wait)";
    host =
      mkOpt types.str "forgejo.pyn.ru"
        "Default Forgejo host, exported as FJ_FALLBACK_HOST, used when a command names no host and the git remote is not a Forgejo remote.";
  };

  config = mkIf cfg.enable {
    sops.secrets.forgejo_token = {
      sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
    };

    home.packages = [ wrapper ];
  };
}
