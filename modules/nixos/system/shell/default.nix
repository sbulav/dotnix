{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.shell;
in
{
  options.system.shell = {
    enable = mkBoolOpt true "Whether to enable the fish shell environment";
  };

  config = mkIf cfg.enable {
    # The user's ~/.config/fish is hand-managed dotfiles — home-manager must
    # never own config.fish. Everything fish-facing here goes through the
    # NixOS-level programs.fish (/etc/fish), which fish sources before it.
    environment.systemPackages = with pkgs; [
      eza
      bat
      zoxide
      starship
      nix-search-tv
    ];

    users.defaultUserShell = pkgs.fish;
    users.users.root.shell = pkgs.bashInteractive;

    # `, cmd` + command-not-found suggestions from the pre-built weekly
    # database (nix-index-database nixosModule, injected in flake.nix; it
    # wires programs.nix-index and disables programs.command-not-found).
    programs.nix-index-database.comma.enable = true;

    programs.fish.interactiveShellInit = ''
      function ns --description 'fuzzy search nixpkgs'
        nix-search-tv print | fzf --preview 'nix-search-tv preview {}' --scheme history
      end
    '';

    environment.shellAliases = {
      ".." = "cd ..";
    };

    home.programs.starship.enable = true;
    home.configFile."starship.toml".source = ./starship.toml;

    home.programs.zoxide.enable = true;
  };
}
