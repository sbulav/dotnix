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

    programs.fish.enable = true;

    users.users.${cfg.name} = {
      home = "/Users/${cfg.name}";
      shell = pkgs.fish;
    };
  };
}
