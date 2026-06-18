{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.user;
in
{
  options.custom.user = with types; {
    enable = mkBoolOpt false "Whether to configure the primary macOS user.";
    name = mkOpt str "sab" "The name of the existing macOS user account.";
    fullName = mkOpt str "Sergei Bulavintsev" "The full name of the macOS user.";
    email = mkOpt str "bulavintsev.sergey@gmail.com" "The email address of the macOS user.";
  };

  config = mkIf cfg.enable {
    system.primaryUser = cfg.name;

    programs.fish = {
      enable = true;
      shellAliases = {
        nixup = "darwin-rebuild switch --flake ~/dotnix";
        nixt = "darwin-rebuild build --flake ~/dotnix";
        nixclean = "nix-collect-garbage -d && nix-store --gc && nix-store --optimise -vvv";
      };
    };

    # nix-darwin does not auto-chsh existing users; after rebuild run once:
    #   chsh -s /run/current-system/sw/bin/fish
    environment.shells = [ pkgs.fish ];

    users.users.${cfg.name} = {
      home = "/Users/${cfg.name}";
    };
  };
}
