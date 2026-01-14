{
  lib,
  pkgs,
  stdenv,
  makeWrapper,
  gnupg,
  coreutils,
  ...
}:
stdenv.mkDerivation {
  pname = "gpg-smart-sign";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/gpg-smart-sign << 'EOF'
    #!/usr/bin/env bash
    # Smart GPG wrapper that automatically selects YubiKey key when available
    # Falls back to configured key when YubiKey is not present

    set -euo pipefail

    # YubiKey key ID (set by configuration)
    YUBIKEY_KEY_ID="15DB4B4A58D027CB73D0E911D06334BAEC6DC034"
    # Fallback key ID (password-protected key)
    FALLBACK_KEY_ID="7C43420F61CEC7FB"

    # Check if YubiKey is present and has a signature key configured
    check_yubikey() {
      # Check if card is present (redirect stderr to avoid noise)
      if ! ${gnupg}/bin/gpg --card-status &>/dev/null; then
        return 1
      fi

      # Extract signature key from card status
      local card_key=$(${gnupg}/bin/gpg --card-status 2>/dev/null | grep "Signature key" | cut -d: -f2 | tr -d ' ')

      # Check if key exists and is not "[none]"
      if [ -n "$card_key" ] && [ "$card_key" != "[none]" ]; then
        return 0
      fi

      return 1
    }

    # Check if YubiKey is available
    if check_yubikey; then
      # YubiKey is available - use it as-is
      exec ${gnupg}/bin/gpg "$@"
    else
      # YubiKey not available - replace YubiKey key ID with fallback key in arguments
      new_args=()
      for arg in "$@"; do
        # Replace any occurrence of YubiKey key ID with fallback key ID
        new_arg="''${arg//$YUBIKEY_KEY_ID/$FALLBACK_KEY_ID}"
        new_args+=("$new_arg")
      done
      exec ${gnupg}/bin/gpg "''${new_args[@]}"
    fi
    EOF

    chmod +x $out/bin/gpg-smart-sign
  '';

  meta = with lib; {
    description = "Smart GPG wrapper for automatic YubiKey detection and fallback";
    longDescription = ''
      A wrapper around GPG that automatically detects YubiKey presence
      and intelligently selects between YubiKey-based signing and
      password-based key signing for git commits.
    '';
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [];
  };
}
