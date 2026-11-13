# mba13: Determinate Nix to upstream Nix

The flake no longer carries Determinate Nix. Until `mba13` is migrated, any
`sys rebuild` there stops before activation with "Determinate Nix is still
installed" — that is the cue for this runbook. There is no supported in-place
switch: Determinate is uninstalled (which erases `/nix`) and upstream Nix is
installed fresh. Plan for about 30 minutes on a working network.

What survives: everything under `/Users/sab` — the `~/dotnix` checkout, the
sops age key, Homebrew. What is lost: the store, old system generations, and
anything installed with `nix profile`.

## Before

1. CI is green for the commit you will build, including "Build Darwin mba13"
   — that run also pushes the closure to `dotnix.cachix.org`, so the
   bootstrap downloads instead of compiling.
2. On the Mac: `git -C ~/dotnix status` is clean and pushed, and
   `~/.config/sops/age/keys.txt` exists.
3. Note anything from `nix profile list` you want back.

## Migrate

1. Remove nix-darwin first. Removing Nix while nix-darwin is installed leaves
   a broken `/etc/ssl/certs` symlink that breaks every download.

   ```sh
   sudo darwin-uninstaller
   ```

   It also resets the login shell to `/bin/zsh`.

2. Remove Determinate Nix, then reboot (clears `/run` and the `/nix` volume):

   ```sh
   sudo /nix/nix-installer uninstall
   sudo reboot
   ```

3. Install upstream Nix with the community installer, trusting the dotnix
   cache for the bootstrap:

   ```sh
   curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes \
     --extra-conf "extra-substituters = https://dotnix.cachix.org" \
     --extra-conf "extra-trusted-public-keys = dotnix.cachix.org-1:/T5Rhb8DkIIAU5wwL2YnMqMsNUkIcOxCIaHUKSaLAVs="
   ```

4. In a new terminal, bootstrap nix-darwin from the flake's own pin:

   ```sh
   cd ~/dotnix && git pull
   nix build .#darwinConfigurations.mba13.system
   sudo ./result/sw/bin/darwin-rebuild switch --flake .#mba13
   ```

   If activation stops with "Unexpected files in /etc", rename each listed
   file to `<file>.before-nix-darwin` and run the `switch` again.

5. Restore the login shell: `chsh -s /run/current-system/sw/bin/fish`.

## Verify

- `nix --version` prints `nix (Nix) 2.x` — no "Determinate".
- `readlink /etc/nix/nix.conf` points into `/etc/static`.
- `nix config show substituters` lists beez, dotnix and cache.nixos.org.
- `/usr/local/bin/determinate-nixd` does not exist.
- `sys rebuild` works.

## If it goes wrong

Before step 1 nothing has changed. After step 2, the way back is reinstalling
Determinate (`curl -fsSL https://install.determinate.systems/nix | sh -s -- install`)
and rebuilding from `0a9984b`, the last commit with the `determinate` input.

## After

Delete the Determinate guard in `modules/darwin/system/nix/default.nix` and
this file, then finish the cleanup on beez: privoxy and its proxy environment
only route Determinate hosts.
