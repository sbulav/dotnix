# YubiKey PAM authentication

[This module](default.nix) enables U2F authentication for the `login` and
`sudo` PAM services. A registered YubiKey can satisfy authentication with a
touch. When U2F fails, PAM continues through the remaining enabled methods
for that service. Noctalia's lock screen uses `login`.

`hardware.yubikey.smartcard.enable` adds GPG, PC/SC tools, and the GPG agent.
For Git signatures, follow the
[YubiKey GPG guide](../../../../docs/yubikey-gpg-setup.md).

## Register a key

Run as the user who will authenticate. For a first registration, create the
directory and write the mapping. The shell option prevents overwriting an
existing mapping.

```sh
mkdir -p ~/.config/Yubico
(set -C; pamu2fcfg > ~/.config/Yubico/u2f_keys)
```

To add a key to an existing mapping, insert the new key and append its
registration.

```sh
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys
```

## Verify authentication

Keep an authenticated terminal open while testing. Run `sudo -k` and
`sudo -v` to test a fresh authentication with the YubiKey. Lock and unlock
the Noctalia session to test `login`. Repeat with the key removed and verify
the configured fallback can unlock the session.

If PAM skips the key, check that `~/.config/Yubico/u2f_keys` exists for the
user and that `/etc/pam.d/login` and `/etc/pam.d/sudo` include `pam_u2f.so`.
For more detail during troubleshooting, use `security.pam.u2f.settings.debug`.
