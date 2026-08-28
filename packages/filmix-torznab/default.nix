# filmix-torznab: Torznab bridge for Filmix PRO+ (.torrent downloads).
#
# Filmix's search returns posts while torrents live one hop away on
# /download/{post_id} with several quality variants per post — beyond
# what a Cardigann YAML can express, hence this small service. See the
# module that runs it: modules/nixos/containers/prowlarr (enableFilmix).
{
  python3,
  stdenvNoCC,
  makeWrapper,
  ...
}:
let
  pythonEnv = python3.withPackages (ps: [
    ps.requests
    ps.beautifulsoup4
    # so HTTPS_PROXY=socks5h://... in the env file just works
    ps.pysocks
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "filmix-torznab";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${pythonEnv}/bin/python -m py_compile filmix_torznab.py
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0644 filmix_torznab.py $out/share/filmix-torznab/filmix_torznab.py
    makeWrapper ${pythonEnv}/bin/python $out/bin/filmix-torznab \
      --add-flags $out/share/filmix-torznab/filmix_torznab.py
    runHook postInstall
  '';

  meta = {
    description = "Torznab indexer bridge for Filmix PRO+ torrent downloads";
    mainProgram = "filmix-torznab";
  };
}
