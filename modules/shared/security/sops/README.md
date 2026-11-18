# SOPS secrets

Commit encrypted YAML under `secrets/`. Edit it with `sops` from the
repository root so it uses [`.sops.yaml`](../../../../.sops.yaml) for recipient
selection. Keep decrypted values and private keys out of Git.

[`flake.nix`](../../../../flake.nix) imports upstream sops-nix for all systems
and Home Manager profiles. It imports [this shared module](default.nix)
for Home Manager. NixOS has a separate
[system wrapper](../../../nixos/system/security/sops/default.nix).

## Home Manager

Set `custom.security.sops.enable = true` in the user profile. The shared
module defaults to `secrets/<user>/default.yaml` and uses the user's Age key
in `~/.config/sops/age/keys.txt`. Set `commonSecrets.enableCredentials` to
install the `env_credentials` secret. Set `defaultSopsFile` to a path resolved
with `lib.snowfall.fs.get-file` when the profile needs a different encrypted
file. The [`mz` home profile](../../../../homes/x86_64-linux/sab@mz/default.nix)
shows the common settings.

## NixOS

Enable `custom.security.sops` and set `defaultSopsFile` to the host's
encrypted file. Here is the host pattern with the file used on `zanoza`.

```nix
custom.security.sops = {
  enable = true;
  sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  defaultSopsFile = lib.snowfall.fs.get-file "secrets/zanoza/default.yaml";
};
```

For a secret in a different encrypted file, set its `sopsFile` explicitly.
Follow the consuming module for owner, mode, and restart behavior. Reuse the
existing templates in [`lib.custom.secrets`](../../../../lib/default.nix)
when their settings match the consumer.
