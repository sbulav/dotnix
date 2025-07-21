{
  inputs,
  mkShell,
  pkgs,
  system,
  namespace,
  ...
}:
mkShell {
  packages = with pkgs; [
    deadnix
    nh
    statix
    sops
  ];

  shellHook = ''
    echo 🔨 Welcome to ${namespace}


  '';
}
