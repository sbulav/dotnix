# YubiKey GPG commit signing

The [`mz`](../homes/x86_64-linux/sab@mz/default.nix) and
[`mba13`](../homes/aarch64-darwin/sab@mba13/default.nix) profiles enable
automatic commit signing with [`gpg-smart-sign`](../packages/gpg-smart-sign/default.nix).
The wrapper passes Git's configured YubiKey fingerprint to GPG when a card
reports a signature key. If that card check fails, it substitutes the local
fallback key ID. Git's signing key and the wrapper's `YUBIKEY_KEY_ID` must
match. The wrapper defines both key IDs.

## Set up a host

1. Confirm the intended Home Manager profile is active. Open a new terminal
   so the [GPG module](../modules/home/security/gpg/default.nix) can start the
   agent and set `GPG_TTY`. On `mz`, the
   [YubiKey hardware module](../modules/nixos/hardware/yubikey/README.md)
   also enables smartcard tools.
2. Insert the YubiKey and run `gpg --card-status`. Confirm the `Signature key`
   matches the fingerprint in the host's Git configuration. For a new, blank
   card, use `gpg --card-edit`, then `admin` and `generate` to provision it.
   After replacing the signing key, update the wrapper and both Home Manager
   profiles.
3. Run `gpg --list-secret-keys --keyid-format LONG`. Confirm the local keyring
   has the card's signing key and the fallback secret key identified by
   `FALLBACK_KEY_ID`. The fallback needs to be usable with the YubiKey unplugged.
4. For GitHub verification, export the public keys and add them under
   **Settings → SSH and GPG keys**. Run `gpg --armor --export KEY_ID` for each
   key, substituting the corresponding fingerprint or key ID.

## Verify both signing paths

Run these commands on the target host in a disposable repository to pick up
the Home Manager Git settings without any project overrides. Start with the
YubiKey inserted.

```sh
signing_test=$(mktemp -d)
git -C "$signing_test" init -q
git -C "$signing_test" config --get gpg.program
git -C "$signing_test" config --get user.signingkey
git -C "$signing_test" config --get commit.gpgsign
git -C "$signing_test" commit --allow-empty -m 'Test YubiKey signing'
git -C "$signing_test" log -1 --format='%G? %GP %GF'
```

Check that `gpg.program` ends in `gpg-smart-sign`, `user.signingkey` matches
the card, and `commit.gpgsign` is `true`. The signature should be good (`G`,
or `U` if its validity is unknown to the local trust database). Compare the
reported primary and signing fingerprints with the card key.

Unplug the card and verify the fallback using the same temporary repository.

```sh
git -C "$signing_test" commit --allow-empty -m 'Test fallback signing'
git -C "$signing_test" log -1 --format='%G? %GP %GF'
```

Confirm the signature is good and the primary fingerprint matches the local
fallback key.

## Troubleshoot

- If the card is missing from `gpg --card-status`, reconnect it and retry. On
  `mz`, check `systemctl status pcscd.socket` and use `pcsc_scan` to inspect
  smartcard detection.
- If Git fails with the card inserted, compare `user.signingkey` with the
  wrapper's `YUBIKEY_KEY_ID` and the card's signing key. For a missing PIN or
  passphrase prompt, check that `GPG_TTY` matches `tty` and open a fresh terminal.
- If fallback fails, verify that the fallback secret key is available locally
  and that the configured `user.signingkey` matches the fingerprint the wrapper
  substitutes.
