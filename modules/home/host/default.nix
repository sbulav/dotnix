{
  lib,
  config,
  pkgs,
  host ? null,
  format ? "unknown",
  ...
}: let
  inherit (lib) types;
  inherit (lib.custom) mkOpt;
in {
  options.custom.host = {
    name = mkOpt (types.nullOr types.string) host "The host name.";
  };
}
