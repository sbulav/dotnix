{
  config,
  lib,
  inputs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.nix;
in
{
  options.custom.tools.nix = with types; {
    enable = mkBoolOpt false "Override Determinate Nix's substituter/nix-path injection via a user nix.conf.";

    substituters =
      mkOpt (listOf str)
        [
          "http://beez.sbulav.ru:5000?priority=10" # local nix-cache-builder (serves shared FODs to darwin too)
          "https://dotnix.cachix.org?priority=10"
          "https://cache.nixos.org?priority=20"
        ]
        "Substituters for the user nix.conf. Replaces Determinate's resolved list (lower priority = checked first).";

    trustedPublicKeys = mkOpt (listOf str) [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8="
      "dotnix.cachix.org-1:/T5Rhb8DkIIAU5wwL2YnMqMsNUkIcOxCIaHUKSaLAVs="
    ] "Trusted public keys to add (additive, via extra-trusted-public-keys).";

    nixPath =
      mkOpt str "nixpkgs=${inputs.nixpkgs}"
        "nix-path for ad-hoc <nixpkgs> (nix-shell -p). Defaults to the pinned flake nixpkgs store path.";
  };

  # Determinate's daemon writes /etc/nix/nix.conf (marked "do not modify") and
  # appends, *after* the nix.custom.conf include:
  #   extra-substituters = https://install.determinate.systems
  #   extra-nix-path     = nixpkgs=flake:.../nixpkgs-weekly/*.tar.gz
  # The install.determinate.systems cache is intermittently flaky (SSL EOF spam
  # on every fetch), and the weekly nixpkgs path re-unpacks from flakehub. The
  # `extra-*` keys are appended by the daemon binary at runtime, so there is no
  # Nix option to remove them system-side.
  #
  # Nix reads this user nix.conf *after* /etc/nix/nix.conf, and a plain (non-
  # `extra-`) key replaces the accumulated value — so this wins. sab is a
  # trusted user on every host, so the daemon honours the substituter override.
  config = mkIf cfg.enable {
    # force: some hosts carry a stale hand-written ~/.config/nix/nix.conf
    # (e.g. old cachix mirror lists); HM refuses to clobber unmanaged files
    # without this, and replacing that cruft is the whole point of this module.
    xdg.configFile."nix/nix.conf" = {
      force = true;
      text = ''
        substituters = ${concatStringsSep " " cfg.substituters}
        extra-trusted-public-keys = ${concatStringsSep " " cfg.trustedPublicKeys}
        nix-path = ${cfg.nixPath}
      '';
    };
  };
}
