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

    # Check if YubiKey is present and has a signature key configured
    check_yubikey() {
      if ! command -v gpg &> /dev/null; then
        return 1
      fi

      # Check if card is present (redirect stderr to avoid noise)
      if ! gpg --card-status &>/dev/null; then
        return 1
      fi

      # Extract signature key from card status
      local card_key=$(gpg --card-status 2>/dev/null | grep "Signature key" | cut -d: -f2 | tr -d ' ')

      # Check if key exists and is not "[none]"
      if [ -n "$card_key" ] && [ "$card_key" != "[none]" ]; then
        return 0
      fi

      return 1
    }

    # Try to use YubiKey, fall back to standard GPG
    if check_yubikey; then
      # YubiKey is available with a signing key - use it
      # GPG will automatically select the key from the card
      exec ${gnupg}/bin/gpg "$@"
    else
      # YubiKey not available or no key - use standard GPG
      # This will use the default key configured in git (user.signingkey)
      exec ${gnupg}/bin/gpg "$@"
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
