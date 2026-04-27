{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf types;
  inherit (lib.custom) mkOpt;

  cfg = config.custom.theme;

  palettes = {
    vu-neon = import ./palettes/vu-neon.nix;
    cyberdream = import ./palettes/cyberdream.nix;
  };
in
{
  options.custom.theme = {
    name = mkOpt (types.enum (builtins.attrNames palettes)) "vu-neon" ''
      Active theme name. Selects the palette used by waybar/mako/hyprland/etc.
    '';

    colors = mkOpt (types.attrsOf types.str) { } ''
      Resolved palette for the active theme. Hex values are stored without a
      leading '#' so they can be embedded into both CSS and Hyprland rgba()
      literals without per-call stripping.
    '';
  };

  config = mkIf (palettes ? ${cfg.name}) {
    custom.theme.colors = palettes.${cfg.name};
  };
}
