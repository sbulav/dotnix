# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  pkgs,
  lib,
  ...
}: let
  system = "x86_64-linux";
  hostName = "zanoza";
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

  custom.security.sops = {
    enable = true;
    sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/saz/default.yaml";
  };

  users.users.sab.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDH2vxB14+ZGFFgtQ6UQ6zw33r/4e/vkMIzNKeaTnDRHmmfnjDSU5oXWt7OSCZQw8zPSbzPV7QPKC9MwEdsl9ZXr4kVxAvN/d/oI/cBU/77tMDW/m1d+SEqhztNrBfpSIavuCT+K9l1vMr/R4qoRxSfLRVsBhr3Xfk3bxZ2vh9dsefZXbL4/ebzW74RUoh1GccPqvBQJxP/+wYsyspn3lsmEi2AbIJprR6fN2Vb3pTW/D0E7k2iIcuBOd1hsw3mn5e2OpXOG2R0XcssBjlquS23up3sIujbw46gITIe1+kCLnmCfGXRDOmcUfB4ySwUlFma8RjcZg7vTGUe47PNJmo3 sab@fedoraz.sbulav.tk"
  ];

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  custom.containers = {
    traefik = {
      enable = true;
      cf_secret_file = "secrets/zanoza/default.yaml";
      domain = "sbulav.ru";
    };
    homepage = {
      enable = true;
      host = "home.sbulav.ru";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.101";
    };
    authelia = {
      enable = true;
      host = "authelia.sbulav.ru";
      secret_file = "secrets/zanoza/default.yaml";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.102";
    };
    adguard = {
      enable = true;
      host = "adguard.sbulav.ru";
      rewriteAddress = "192.168.89.207";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.104";
    };
    flood = {
      enable = true;
      host = "flood.sbulav.ru";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.105";
    };
    nextcloud = {
      enable = true;
      host = "nextcloud.sbulav.ru";
      secret_file = "secrets/zanoza/default.yaml";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.106";
    };
    jellyfin = {
      enable = false;
      host = "jellyfin.sbulav.ru";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.107";
    };
  };

  environment.systemPackages = with pkgs; [
    alejandra
    nixd # LSP for nix
  ];
  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "24.11";
  # ======================== DO NOT CHANGE THIS ========================
}
