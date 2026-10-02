{ runCommand, lua, ... }:
runCommand "quake-console-test" { nativeBuildInputs = [ lua ]; } ''
  lua ${./test.lua} ${../../modules/home/desktop/addons/quake-console/quake-console.lua}
  touch "$out"
''
