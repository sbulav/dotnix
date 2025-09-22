# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{
  pkgs,
  lib,
  ...
}: let
  system = "x86_64-linux";
  hostName = "beez";
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  suites.server.enable = true; # Enables the basics, like neovim, ssh, etc.
  suites.desktop.enable = false;
  suites.develop.enable = false;

  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        openFirewall = true;
        port = 9100;
      };
      smartctl = {
        enable = true;
        port = 9633;
        openFirewall = true;
        devices = ["/dev/sda"]; # Adjust based on your disks (run lsblk to check)
      };
    };
  };

  networking.firewall.allowedTCPPorts = [9100 9633];

  custom.services.linuxTransparentProxy = {
    enable = true;
    v2rayAHost = "192.168.89.207";
    v2rayAPort = 1080;
    listenPort = 12345;
    interface = "eth0";
    tcpPorts = [80 443]; # Or [] for all TCP
  };

  custom.security.sops = {
    enable = true;
    sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/beez/default.yaml";
  };

  users.users.sab.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDH2vxB14+ZGFFgtQ6UQ6zw33r/4e/vkMIzNKeaTnDRHmmfnjDSU5oXWt7OSCZQw8zPSbzPV7QPKC9MwEdsl9ZXr4kVxAvN/d/oI/cBU/77tMDW/m1d+SEqhztNrBfpSIavuCT+K9l1vMr/R4qoRxSfLRVsBhr3Xfk3bxZ2vh9dsefZXbL4/ebzW74RUoh1GccPqvBQJxP/+wYsyspn3lsmEi2AbIJprR6fN2Vb3pTW/D0E7k2iIcuBOd1hsw3mn5e2OpXOG2R0XcssBjlquS23up3sIujbw46gITIe1+kCLnmCfGXRDOmcUfB4ySwUlFma8RjcZg7vTGUe47PNJmo3 sab@fedoraz.sbulav.tk"
  ];

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  environment.systemPackages = with pkgs; [
    alejandra
    nixd # LSP for nix
    smartmontools
  ];
  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "25.05";
  # ======================== DO NOT CHANGE THIS ========================
}
