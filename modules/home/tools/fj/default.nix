# fj (forgejo-cli): issues, pull requests, comments, labels and milestones on
# Forgejo. Actions logs and reruns are fj-ex's job (modules/home/tools/fj-ex).
#
# fj reads its credential from keys.json in its data directory and takes no
# token from the environment. That file is rendered here from the sops secret
# (secrets/sab, key forgejo_token), so the token never lands in the Nix store.
# fj rewrites keys.json only from `fj auth ...` or an OAuth refresh; a plain
# application token is read-only use, so the managed file stays as rendered.
# Change the credential in sops, not with `fj auth login`.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf types;
  inherit (lib.custom) mkOpt;

  cfg = config.custom.tools.fj;

  # ProjectDirs::from("", "forgejo-cli", "forgejo-cli").data_dir()
  dataDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/forgejo-cli.forgejo-cli"
    else
      "${config.xdg.dataHome}/forgejo-cli";
in
{
  options.custom.tools.fj = {
    enable = mkEnableOption "fj (forgejo-cli: issues, pull requests, labels, milestones)";
    host = mkOpt types.str "forgejo.pyn.ru" "Forgejo host the stored token belongs to.";
  };

  config = mkIf cfg.enable {
    sops.secrets.forgejo_token = {
      sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
    };

    sops.templates."forgejo-cli-keys.json" = {
      content = builtins.toJSON {
        hosts.${cfg.host} = {
          type = "Application";
          token = config.sops.placeholder.forgejo_token;
        };
      };
      path = "${dataDir}/keys.json";
      mode = "0600";
    };

    home.packages = [ pkgs.unstable.forgejo-cli ];
  };
}
