# fj-ex: Forgejo Actions from the command line (job logs, rerun, cancel, wait).
# fj (forgejo-cli) covers issues and pull requests but only lists Actions
# tasks; fj-ex adds job logs, rerun, cancel and wait through Forgejo's REST API
# (logs since v16, rerun since v17). Not in nixpkgs, so it is built from the
# crates.io release here.
{
  lib,
  rustPlatform,
  fetchCrate,
  pkg-config,
  cmake,
  openssl,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "fj-ex";
  version = "0.1.14";

  src = fetchCrate {
    pname = "forgejo-cli-ex";
    inherit (finalAttrs) version;
    hash = "sha256-DrHNPPWHx2dRGqVjDRm3ERNyib9GYhd/k+2XQCHLGGU=";
  };

  cargoHash = "sha256-zEqGAqZO242F+ZMiYGCa3RF6VGkBfJ5C7caoJ/XAo0A=";

  nativeBuildInputs = [
    pkg-config
    cmake
  ];
  buildInputs = [ openssl ];

  # The test suite drives real Forgejo and Gitea servers in Docker.
  doCheck = false;

  meta = {
    description = "Forgejo CLI extension for Actions logs, reruns, cancels and waits";
    homepage = "https://github.com/JKamsker/forgejo-cli-ex";
    license = lib.licenses.lgpl3Plus;
    mainProgram = "fj-ex";
    platforms = lib.platforms.unix;
  };
})
