{
  pkgs,
  lib,
  inputs,
  config,
  ...
}:
let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.system}.full;
in
{
  imports = [ ./hardware-configuration.nix ];
  system.wallpaper = "${wallpapers}/share/wallpapers/cities/1-osaka-jade-bg.jpg";
  # Enable Bootloader
  system.boot.efi.enable = true;
  system.battery.enable = false; # Only for laptops, they will still work without it, just improves battery life
  hardware = {
    fingerprint.enable = false;
    bluetooth.enable = true;
    bluetoothmy.enable = true;
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
  services.ssh.enable = true;
  custom.security.sops = {
    enable = true;
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/porez/default.yaml";
  };

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  # Stylix - Centralized Theme Management
  # TODO: Fix stylix base16 duplication error
  # Issue: stylix.base16 is calculated twice (once for system, once for home-manager)
  # causing "The option `home-manager.users.sab.stylix.base16' is read-only, but it's set multiple times"
  # Temporarily disabled until resolved
  # custom.desktop.stylix = {
  #   enable = true;
  #   theme = "cyberdream";
  #   wallpaper = config.system.wallpaper;
  # };
  
  # Disable grub theming (system-level only option)
  # stylix.targets.grub.enable = false;

  custom.services.prometheus-exporters = {
    enable = true;
    node = {
      enable = true;
      port = 9100;
      openFirewall = true;
    };
    smartctl = {
      enable = true;
      port = 9633;
      openFirewall = true;
      devices = [ "/dev/nvme0n1" ];
    };
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
