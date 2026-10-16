{ runCommand, lua, ... }:
runCommand "clamshell-test" { nativeBuildInputs = [ lua ]; } ''
  lua ${./test.lua} ${../../modules/home/desktop/addons/system-polish/clamshell.lua}
  touch "$out"
''
