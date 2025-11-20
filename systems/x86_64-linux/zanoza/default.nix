# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  pkgs,
  lib,
  ...
}:
let
  system = "x86_64-linux";
  hostName = "zanoza";
in
{
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
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/zanoza/default.yaml";
  };

  users.users.sab.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDH2vxB14+ZGFFgtQ6UQ6zw33r/4e/vkMIzNKeaTnDRHmmfnjDSU5oXWt7OSCZQw8zPSbzPV7QPKC9MwEdsl9ZXr4kVxAvN/d/oI/cBU/77tMDW/m1d+SEqhztNrBfpSIavuCT+K9l1vMr/R4qoRxSfLRVsBhr3Xfk3bxZ2vh9dsefZXbL4/ebzW74RUoh1GccPqvBQJxP/+wYsyspn3lsmEi2AbIJprR6fN2Vb3pTW/D0E7k2iIcuBOd1hsw3mn5e2OpXOG2R0XcssBjlquS23up3sIujbw46gITIe1+kCLnmCfGXRDOmcUfB4ySwUlFma8RjcZg7vTGUe47PNJmo3 sab@fedoraz.sbulav.tk"
  ];

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  custom.services = {
    ipcamCleanup.enable = true;
    logrotate = {
      enable = true;
      logFiles = [
        "/tank/authelia/logs/*.log"
        "/tank/torrents/log/*.log"
        "/tank/traefik/logs/*.log"
        "/tank/v2raya/logs/*.log"
      ];
    };
  };

  custom.containers = {
    # {{{ Services on OS
    loki = {
      enable = true;
    };
    prometheus = {
      enable = true;
      host = "prometheus.sbulav.ru";
      smartctl_devices = [
        "/dev/nvme0n1"
        "/dev/sda"
        "/dev/sdb"
        "/dev/sdc"
        "/dev/sdd"
      ];
    };
    msmtp = {
      enable = true;
      secret_file = "secrets/zanoza/default.yaml";
    };
    restic = {
      enable = true;
      backup_host = "192.168.92.194";
      secret_file = "secrets/zanoza/default.yaml";
    };
    ups = {
      enable = true;
    };
    nfs = {
      enable = true;
      filesystems = [
        "/tank/torrents"
        "/tank/video"
        "/tank/ipcam"
      ];
      restrictedClients = [ "192.168.80.0/20" ];
    };
    traefik = {
      enable = true;
      cf_secret_file = "secrets/zanoza/default.yaml";
      domain = "sbulav.ru";
    }; # }}}
    # {{{ Services in nixos-containers
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
      hostMappings = [
        {
          hostname = "beez";
          ip = "192.168.92.194";
        }
        {
          hostname = "beez.sbulav.ru";
          ip = "192.168.92.194";
        }
        {
          hostname = "mz";
          ip = "192.168.89.200";
        }
        {
          hostname = "mz.sbulav.ru";
          ip = "192.168.89.200";
        }
      ];
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
      enable = true;
      host = "jellyfin.sbulav.ru";
      secret_file = "secrets/zanoza/default.yaml";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.107";
    };
    v2raya = {
      enable = true;
      host = "v2raya.sbulav.ru";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.108";
    };
    immich = {
      enable = true;
      host = "immich.sbulav.ru";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.109";
      secret_file = "secrets/zanoza/default.yaml";
    };
    grafana = {
      enable = true;
      host = "grafana.sbulav.ru";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.112";
      secret_file = "secrets/zanoza/default.yaml";
    }; # }}}
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "beez";
      static_configs = [
        {
          targets = [
            "beez:9100"
            "beez:9633"
          ];
          labels = {
            instance = "beez";
            role = "server";
          };
        }
      ];
    }
    {
      job_name = "mz";
      static_configs = [
        {
          targets = [
            "mz:9100"
            "mz:9633"
          ];
          labels = {
            instance = "mz";
            role = "desktop";
          };
        }
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    nixd # LSP for nix
    smartmontools
  ];
  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "25.11";
  # ======================== DO NOT CHANGE THIS ========================
}
