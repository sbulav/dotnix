# herdr-remote relay: polls the local herdr server, accepts push events
# (HTTP POST + WebSocket + UDP), broadcasts agent state to clients over
# WebSocket. Source comes from the herdr-remote flake input (not a flake).
{
  lib,
  inputs,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "herdr-relay";
  version = "0.5.0";

  src = inputs.herdr-remote;
  format = "other";

  patches = [
    ./broadcast-empty-agent-list.patch
    ./native-session-lifecycle.patch
    ./structured-output-from-transcript.patch
  ];

  propagatedBuildInputs = with python3Packages; [
    websockets
    zeroconf
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 relay/herdr_relay.py $out/bin/herdr-relay
    runHook postInstall
  '';

  meta = {
    description = "Relay server for monitoring and controlling herdr agents remotely";
    homepage = "https://github.com/dcolinmorgan/herdr-remote";
    license = lib.licenses.agpl3Only;
    mainProgram = "herdr-relay";
  };
}
