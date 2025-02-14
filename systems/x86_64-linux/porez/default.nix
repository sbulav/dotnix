{
  pkgs,
  lib,
  inputs,
  ...
}: let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.system}.full;
in {
  imports = [./hardware-configuration.nix];
  system.wallpaper = "${wallpapers}/share/wallpapers/unorganized/left.jpg";
  # Enable Bootloader
  system.boot.efi.enable = true;
  system.battery.enable = false; # Only for laptops, they will still work without it, just improves battery life
  hardware = {
    fingerprint.enable = false;
    bluetoothmy.enable = false;
    cpu.amd.enable = true;
    gpu.amd.enable = true;
    openglmy.enable = true;
    rgb.openrgb.enable = true;
  };

  # environment.systemPackages = with pkgs; [
  #   # Any particular packages only for this host
  # ];

  # Suites managed by nix, see suites by home-manager in homes
  suites.common.enable = true; # Enables the basics, like audio, networking, ssh, etc.
  suites.desktop.enable = true;
  suites.develop.enable = true;
  suites.games.enable = true;
  custom.security.sops = {
    enable = true;
    sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/porez/default.yaml";
  };

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  # limit systemd journal size
  # https://wiki.archlinux.org/title/Systemd/Journal#Persistent_journals
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
    SystemMaxFileSize=50M
  '';

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "24.11";
  # ======================== DO NOT CHANGE THIS ========================
}
