{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.stdenv.hostPlatform.system}.full;
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
    gpu.intel.enable = true;
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
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/mz/default.yaml";
  };

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  # Enable for printing, configure on http://localhost:631/printers/Pantum_M6550NW_series
  custom.services.avahi.enable = false;
  custom.services.printing.enable = false;

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
      devices = [
        "/dev/nvme0n1"
        "/dev/nvme1n1"
      ];
    };
  };

  # limit systemd journal size
  # https://wiki.archlinux.org/title/Systemd/Journal#Persistent_journals
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
    SystemMaxFileSize=50M
  '';
  # Allow control of lian li galahad II
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0416", ATTR{idProduct}=="7395", MODE="0666", GROUP="users"
  '';

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "25.11";
  # ======================== DO NOT CHANGE THIS ========================
}
