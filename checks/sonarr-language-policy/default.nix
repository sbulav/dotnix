{
  lib,
  runCommand,
  python3,
  sonarr,
  stdenv,
  ...
}:
runCommand "sonarr-language-policy-test"
  {
    nativeBuildInputs = [ python3 ] ++ lib.optionals stdenv.isLinux [ sonarr ];
  }
  (
    if stdenv.isLinux then
      ''
        python3 ${./test.py} ${lib.getExe sonarr} \
          ${../../modules/nixos/containers/sonarr/apply-language-policy.py}
        touch "$out"
      ''
    else
      ''
        PYTHONPYCACHEPREFIX="$TMPDIR/pycache" python3 -m py_compile \
          ${../../modules/nixos/containers/sonarr/apply-language-policy.py}
        touch "$out"
      ''
  )
