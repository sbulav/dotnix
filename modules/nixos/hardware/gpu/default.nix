{
  lib,
  namespace,
  ...
}: let
  inherit (lib.${namespace}) mkBoolOpt;
in {
  options.hardware.gpu = {
    enable = mkBoolOpt false "No-op for setting up hierarchy.";
  };
}
