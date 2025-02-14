{
  lib,
  namespace,
  ...
}: let
  inherit (lib.${namespace}) mkBoolOpt;
in {
  options.hardware.cpu = {
    enable = mkBoolOpt false "No-op used for setting up hierarchy.";
  };
}
