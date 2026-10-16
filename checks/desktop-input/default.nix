{ runCommand, lua, ... }:
runCommand "desktop-input-test" { nativeBuildInputs = [ lua ]; } ''
  lua ${./test.lua} ${../../modules/home/desktop/hyprland/input.lua}
  touch "$out"
''
