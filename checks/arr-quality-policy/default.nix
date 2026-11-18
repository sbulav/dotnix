{
  lib,
  runCommand,
  python3,
  radarr,
  sonarr,
  stdenv,
  ...
}:
runCommand "arr-quality-policy-test"
  {
    nativeBuildInputs = [
      python3
    ]
    ++ lib.optionals stdenv.isLinux [
      radarr
      sonarr
    ];
  }
  (
    if stdenv.isLinux then
      ''
        python3 ${./test.py} radarr ${lib.getExe radarr} \
          ${../../modules/nixos/containers/shared/apply-arr-quality-policy.py}
        python3 ${./test.py} sonarr ${lib.getExe sonarr} \
          ${../../modules/nixos/containers/shared/apply-arr-quality-policy.py}
        touch "$out"
      ''
    else
      ''
        PYTHONPYCACHEPREFIX="$TMPDIR/pycache" python3 -m py_compile \
          ${../../modules/nixos/containers/shared/apply-arr-quality-policy.py}
        touch "$out"
      ''
  )
