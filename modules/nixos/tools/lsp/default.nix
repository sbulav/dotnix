{
  inputs,
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.lsp;
in
{
  options.custom.tools.lsp = with types; {
    enable = mkBoolOpt false "Whether or not to enable lsp utilities.";
  };

  config = mkIf cfg.enable {
    nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
    environment.systemPackages = with pkgs; [
      helm-ls
      lua-language-server # LSP for lua
      marksman # LSP for markdown
      nixd # LSP for nix
      nodejs_22 # Note for LSP servers
      pyright
      ruff
      black
      terraform-ls
      tree-sitter
      vscode-langservers-extracted
      yaml-language-server
      yamllint
    ];
  };
}
