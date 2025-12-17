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
  system = {
    wallpaper = "${wallpapers}/share/wallpapers/cities/1-osaka-jade-bg.jpg";
    # Enable Bootloader
    boot.efi.enable = true;
    battery.enable = true; # Only for laptops, they will still work without it, just improves battery life

    nix.cache-servers = [
      {
        url = "http://beez.sbulav.ru:5000";
        key = "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8=";
        priority = 40;
      }
    ];
  };

  hardware.fingerprint.enable = true;
  hardware.yubikey.enable = true;
  hardware.bluetoothmy.enable = true;

  # environment.systemPackages = with pkgs; [
  #   # Any particular packages only for this host
  # ];

  # Suites managed by nix, see suites by home-manager in homes
  suites.common.enable = true; # Enables the basics, like audio, networking, ssh, etc.
  suites.desktop.enable = true;
  suites.develop.enable = true;

  custom = {
    security.sops = {
      enable = true;
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      defaultSopsFile = lib.snowfall.fs.get-file "secrets/nz/default.yaml";
    };

    virtualisation = {
      virt-manager.enable = true;
      kvm.enable = false;
      podman.enable = true;
    };
  };

  networking.hosts = {
    "192.168.89.207" = [
      "zanoza"
      "zanoza.sbulav.ru"
    ];
    "192.168.92.194" = [
      "beez"
      "beez.sbulav.ru"
    ];
    "192.168.89.200" = [
      "mz"
      "mz.sbulav.ru"
    ];
  };

  # limit systemd journal size
  # https://wiki.archlinux.org/title/Systemd/Journal#Persistent_journals
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
    SystemMaxFileSize=50M
  '';

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "25.11";
  # ======================== DO NOT CHANGE THIS ========================
}
