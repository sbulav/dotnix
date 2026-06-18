{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.cli;
in
{
  options.custom.tools.cli = with types; {
    enable = mkBoolOpt false "Whether to install the portable command-line toolkit.";

    development.enable = mkBoolOpt true "Whether to install language servers, formatters, and linters.";

    kubernetes.enable = mkBoolOpt true "Whether to install Kubernetes command-line tools.";

    extraPackages = mkOpt (listOf package) [ ] "Additional command-line packages to install.";
  };

  config = mkIf cfg.enable {
    home.packages =
      (with pkgs; [
        curl
        dig
        fd
        ffmpeg
        file
        fzf
        iftop
        imagemagick
        ipfetch
        jq
        ripgrep
        rsync
        tree
        unzip
        wget
        yq
        zoxide
      ])
      ++ optionals cfg.kubernetes.enable (
        with pkgs;
        [
          helm-docs
          helmfile
          krew
          kubecolor
          kubectl
          kubectx
          kubernetes-helm
        ]
      )
      ++ optionals cfg.development.enable (
        with pkgs;
        [
          black
          ctags
          helm-ls
          jsonnet-language-server
          lua-language-server
          marksman
          nixd
          nodejs_22
          pyright
          ruff
          shfmt
          stylua
          tree-sitter
          vscode-langservers-extracted
          yaml-language-server
          yamllint
        ]
      )
      ++ cfg.extraPackages;
  };
}
