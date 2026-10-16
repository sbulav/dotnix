{
  pkgs,
  runCommand,
  stdenv,
  writeShellScriptBin,
  python3,
  strace,
  ...
}:
let
  recorder = runCommand "fake-recorder" { nativeBuildInputs = [ stdenv.cc ]; } ''
    mkdir -p "$out/bin"
    cc -Wall -Wextra ${./recorder.c} -o "$out/bin/gpu-screen-recorder"
  '';
  commands = writeShellScriptBin "capture-region" ''
    if [[ -n ''${FAKE_PICKER_GATE:-} ]]; then
      touch "$FAKE_PICKER_GATE.entered"
      while [[ ! -e $FAKE_PICKER_GATE ]]; do sleep 0.05; done
    fi
    printf '0,0 1920x1080\n'
  '';
  hyprland = writeShellScriptBin "hyprctl" ''
    printf '[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}]\n'
  '';
  media = runCommand "fake-media" { } ''
    mkdir -p "$out/bin"
    for name in mpv notify-send; do
      printf '#!%s\nexit 0\n' ${pkgs.runtimeShell} > "$out/bin/$name"
    done
    for name in ffmpeg ffprobe; do
      printf '#!%s\nexit 1\n' ${pkgs.runtimeShell} > "$out/bin/$name"
    done
    chmod +x "$out/bin/"*
  '';
  package = pkgs.callPackage ../../packages/record-screen {
    pkgs = pkgs // {
      custom = pkgs.custom // {
        capture-region = commands;
      };
    };
    gpu-screen-recorder = recorder;
    inherit hyprland;
    ffmpeg = media;
    libnotify = media;
    mpv = media;
  };
in
if stdenv.hostPlatform.isLinux then
  runCommand "record-screen-test" { nativeBuildInputs = [ python3 ]; } ''
    python ${./test.py} ${package}/bin/record-screen ${recorder}/bin/gpu-screen-recorder ${strace}/bin/strace
    touch "$out"
  ''
else
  # Snowfall exposes checks on every system; this CLI needs Linux /proc,
  # inotify and pidfds. The compositor behavior checks remain portable.
  runCommand "record-screen-test-linux-only" { } ''
    echo "Skipping Linux recording lifecycle checks on ${stdenv.hostPlatform.system}"
    touch "$out"
  ''
