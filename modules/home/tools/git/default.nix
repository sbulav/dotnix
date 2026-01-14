{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.git;
  user = config.custom.user;
in
{
  options.custom.tools.git = with types; {
    enable = mkBoolOpt false "Whether or not to install and configure git.";
    userName = mkOpt types.str user.fullName "The name to configure git with.";
    userEmail = mkOpt types.str user.email "The email to configure git with.";
    signingKey = mkOpt types.str "7C43420F61CEC7FB" "The key ID to sign commits with.";
    enableSigning = mkBoolOpt true "Whether to enable GPG commit signing.";
    gpgProgram = mkOpt types.str "gpg" "The GPG program to use for signing.";
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      lfs = enabled;
      settings = {
        user = {
          name = cfg.userName;
          email = cfg.userEmail;
          signingkey = cfg.signingKey;
        };
        commit = {
          gpgsign = cfg.enableSigning;
        };
        gpg = {
          program = cfg.gpgProgram;
        };
        init = {
          defaultBranch = "master";
          templatedir = "~/.git_template";
          whitespace = "trailing-space,space-before-tab";
        };
        core = {
          pager = "bat";
        };
        pull = {
          rebase = true;
        };
        push = {
          autoSetupRemote = true;
        };
        merge = {
          tool = "nvimdiff";
          conflictstyle = "diff3";
        };
        diff = {
          tool = "nvimdiff";
        };
        difftool = {
          prompt = false;
        };
        mergetool = {
          prompt = false;
        };
        alias = {
          st = "status -sb";
          lga = "log --oneline --all --decorate --graph --color";
          lg = "log --pretty=lg";
          glg = "log --graph --pretty=lg";
          slg = "stash list --pretty=reflg";
          hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
        };
      };
    };
  };
}
