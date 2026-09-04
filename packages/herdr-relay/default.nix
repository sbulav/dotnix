# herdr-relay: WebSocket relay for monitoring and approving herdr agents remotely.
# Source comes from the herdr-remote flake input (plain repo, not a flake).
# Packaging mirrors upstream nix/package.nix, adapted to our flake inputs.
{
  lib,
  inputs,
  stdenvNoCC,
  python3,
  makeWrapper,
  openssh,
}:
let
  version = "0.8.5";

  pythonEnv = python3.withPackages (ps: [ ps.websockets ]);
in
stdenvNoCC.mkDerivation {
  pname = "herdr-relay";
  inherit version;

  src = inputs.herdr-remote;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  # The relay reports its own version to clients on connect. If the derivation
  # and RELAY_VERSION disagree, `relay_version` on the wire is a lie, so fail
  # the build instead of shipping it.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    grep -q 'RELAY_VERSION = "${version}"' relay/herdr_relay/config.py || {
      echo "RELAY_VERSION in relay/herdr_relay/config.py does not match package version ${version}" >&2
      exit 1
    }
    runHook postCheck
  '';

  # Layout matters: the package resolves web/ two levels up from itself, and the
  # launcher imports the package from its own directory.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/herdr-relay/relay
    cp relay/herdr-relay.py relay/on_event.py $out/share/herdr-relay/relay/
    cp -R relay/herdr_relay $out/share/herdr-relay/relay/herdr_relay
    cp -R web $out/share/herdr-relay/web

    makeWrapper ${pythonEnv}/bin/python3 $out/bin/herdr-relay \
      --add-flags $out/share/herdr-relay/relay/herdr-relay.py \
      --prefix PATH : ${lib.makeBinPath [ openssh ]}

    runHook postInstall
  '';

  meta = {
    description = "WebSocket relay for monitoring and approving herdr AI agents remotely";
    homepage = "https://github.com/sbulav/herdr-relay";
    license = lib.licenses.agpl3Plus;
    mainProgram = "herdr-relay";
    platforms = lib.platforms.unix;
  };
}
