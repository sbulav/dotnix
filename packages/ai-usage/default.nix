{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  ...
}:
stdenvNoCC.mkDerivation {
  pname = "ai-usage";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0644 ai_usage.py $out/share/ai-usage/ai_usage.py
    makeWrapper ${python3}/bin/python $out/bin/ai-usage-update \
      --add-flags $out/share/ai-usage/ai_usage.py
    runHook postInstall
  '';

  meta = {
    description = "Live Claude Code and Codex subscription limit collector";
    license = lib.licenses.mit;
    mainProgram = "ai-usage-update";
    platforms = lib.platforms.unix;
  };
}
