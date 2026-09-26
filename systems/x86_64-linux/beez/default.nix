# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  system = "x86_64-linux";
  hostName = "beez";
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

  # Disable GPG since nix-cache-builder needs standard SSH agent
  system.security.gpg.enable = mkForce false;
  # FIXING NVME power consumption
  # Apply PS1 at boot for every NVMe controller
  # systemd.services.nvme-cap-ps1-nvme0 = {
  #   description = "Force NVMe power state PS1 (~2.4W)";
  #   wantedBy = ["multi-user.target"];
  #   after = ["local-fs.target"];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = ''
  #       /run/current-system/sw/bin/nvme set-feature -f 2 -V 1 /dev/nvme0 || true
  #     '';
  #   };
  # };

  # # Apply PS1 at boot for every NVMe controller
  # systemd.services.nvme-cap-ps1-nvme1 = {
  #   description = "Force NVMe power state PS1 (~2.4W)";
  #   wantedBy = ["multi-user.target"];
  #   after = ["local-fs.target"];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = ''
  #       /run/current-system/sw/bin/nvme set-feature -f 2 -V 1 /dev/nvme1 || true
  #     '';
  #   };
  # };

  # Containers here use 172.16.65.0/24, which lies inside the 172.16.64.0/18
  # the router routes to zanoza: from the LAN (zanoza included) these
  # addresses are unreachable except through the port forwards below.
  custom.containers.adguard = {
    enable = true;
    publishWeb = false;
    externalInterface = "enp1s0";
    hostAddress = "172.16.65.10";
    localAddress = "172.16.65.104";
    listenAddress = lib.custom.dns.resolverAddresses.beez;
    hostMappings = lib.custom.dns.hostMappings;
  };

  custom.containers = {
    prometheus = {
      enable = true;
      publishWeb = false;
      scrapeConfigs =
        let
          zanoza = lib.custom.dns.hosts.zanoza;
          target = host: address: {
            targets = [ address ];
            labels = {
              inherit host;
              instance = host;
            };
          };
        in
        [
          {
            job_name = "node";
            static_configs = [
              (target "beez" "127.0.0.1:9100")
              (target "zanoza" "${zanoza}:3021")
              (target "mz" "mz:9100")
            ];
          }
          {
            job_name = "smartctl";
            static_configs = [
              (target "beez" "127.0.0.1:9633")
              (target "zanoza" "${zanoza}:9633")
              (target "mz" "mz:9633")
            ];
          }
          {
            job_name = "nut";
            metrics_path = "/ups_metrics";
            static_configs = [
              {
                targets = [ "${zanoza}:9199" ];
                labels = {
                  host = "zanoza";
                  instance = "zanoza";
                  ups = "ups";
                };
              }
            ];
          }
          {
            job_name = "authelia";
            static_configs = [ (target "zanoza" "172.16.64.102:9959") ];
          }
        ];
    };
    loki = {
      enable = true;
      retention.enable = true;
    };
    # Published by this host's Traefik (below) so dashboards stay reachable
    # while zanoza or the work site is down. Authelia lives on zanoza, so the
    # public route skips `auth-chain`; Grafana's own login guards it.
    grafana = {
      enable = true;
      publishWeb = true;
      externalMiddlewares = [ "secure-headers" ];
      remoteDashboards = true;
      dataPath = "/var/lib/grafana";
      hostAddress = "172.16.65.10";
      localAddress = "172.16.65.112";
      secret_file = "secrets/beez/monitoring.yaml";
    };
    # Independent ingress for the services published from this host (only
    # Grafana today): wildcard *.sbulav.ru certificate via Cloudflare DNS-01,
    # ports 80/443 forwarded here by the home router. Runs on the host
    # network, so it reaches the Grafana container address directly.
    traefik = {
      enable = true;
      cf_secret_file = "secrets/beez/default.yaml";
      domain = "sbulav.ru";
      dataPath = "/var/lib/traefik";
    };
  };
  custom.services.alloy.enable = true;

  # All monitoring state is on the root NVMe; no zanoza or USB mount dependency.
  # Traefik runs as the first dynamically allocated system user of its
  # ephemeral container (999), the same id the cloudflare env secret is
  # owned by.
  systemd.tmpfiles.rules = [
    "d /var/lib/grafana/data 0750 196 999 -"
    "d /var/lib/traefik 0750 999 999 -"
    "d /var/lib/traefik/certs 0750 999 999 -"
    "d /var/lib/traefik/logs 0750 999 999 -"
  ];
  # Prometheus and Loki listen on the host and take only zanoza's ingress.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s ${lib.custom.dns.hosts.zanoza} -p tcp -m multiport --dports 9090,3030 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -s ${lib.custom.dns.hosts.zanoza} -p tcp -m multiport --dports 9090,3030 -j nixos-fw-accept || true
  '';
  # Evaluation and actual builders are separate processes; cap their aggregate.
  systemd.slices.nix-builds.sliceConfig = {
    CPUQuota = "300%";
    CPUWeight = 20;
    IOWeight = 20;
    MemoryHigh = "8G";
    MemoryMax = "9G";
  };
  systemd.services.nix-daemon.serviceConfig.Slice = "nix-builds.slice";
  systemd.services.nix-cache-builder.serviceConfig.Slice = "nix-builds.slice";
  systemd.services.prometheus.serviceConfig = {
    CPUWeight = 200;
    IOWeight = 200;
    MemoryLow = "512M";
  };
  systemd.services.loki.serviceConfig = {
    CPUWeight = 200;
    IOWeight = 200;
    MemoryLow = "512M";
  };
  systemd.services."container@grafana".serviceConfig = {
    CPUWeight = 200;
    IOWeight = 200;
    MemoryLow = "512M";
  };

  # Scraped by the local Prometheus over loopback only.
  custom.services.prometheus-exporters = {
    enable = true;
    node = {
      enable = true;
      port = 9100;
      openFirewall = false;
    };
    smartctl = {
      enable = true;
      port = 9633;
      openFirewall = false;
      devices = [ "/dev/nvme0n1" ];
    };
  };

  custom.services.zanoza-external-monitoring = {
    enable = true;
    tcpTargets = [
      {
        name = "host_ssh";
        address = "192.168.89.207";
        port = 22;
      }
    ];
    httpTargets = [
      {
        name = "reverse_proxy";
        url = "https://traefik.sbulav.ru";
      }
      {
        name = "homepage";
        url = "https://home.sbulav.ru";
      }
      {
        name = "jellyfin";
        url = "https://jellyfin.sbulav.ru";
      }
      {
        name = "immich";
        url = "https://immich.sbulav.ru";
      }
      {
        name = "opencloud";
        url = "https://opencloud.sbulav.ru";
      }
    ];
    dns = {
      server = "172.16.64.104";
      name = "home.sbulav.ru";
      expectedAddress = "192.168.89.207";
    };
    backup = {
      repositoryPath = "/mnt/ext/backup_zanoza";
      staleAfterSeconds = 36 * 60 * 60;
      # Selectors match how zanoza's restic module writes snapshots. The
      # immich/photos jobs select by path because the `job=` tags only exist
      # once zanoza runs the tagged configuration; opencloud selects by tag so
      # the pre-tag users/-only snapshots do not count as fresh backups.
      jobs = [
        {
          name = "opencloud";
          matchTags = [ "job=opencloud" ];
          expectedPaths = [
            "/tank/opencloud"
            "/var/lib/nixos-containers/opencloud/etc/opencloud"
          ];
          verify = {
            include = "/var/lib/nixos-containers/opencloud/etc/opencloud";
            expectFile = "/var/lib/nixos-containers/opencloud/etc/opencloud/opencloud.yaml";
          };
        }
        {
          name = "immich";
          matchPaths = [ "/tank/immich" ];
          verify = {
            include = "/tank/immich/profile";
            expectFile = "/tank/immich/profile/.immich";
          };
        }
        {
          name = "photos";
          matchPaths = [ "/tank/photos" ];
          verify.include = "/tank/photos/Ideas";
        }
      ];
    };
    telegram.proxyUrl = "socks5h://192.168.89.207:20170";
  };

  # custom.services.linuxTransparentProxy = {
  #   enable = false;
  #   socksHost = "192.168.89.207";
  #   socksPort = 20170;
  #   listenPort = 12345;
  #   interface = "enp1s0";
  #   tcpPorts = [80 443]; # Or [] for all TCP
  # };
  custom.services.nix-cache-builder = {
    enable = true;
    # Touch this volatile file to force the next cache run to build locally.
    remoteBuilderDisableFile = "/run/nix-cache-builder-local-only";
    # Build order: the servers first, so a long desktop build cannot starve
    # them out of the total budget.
    hosts = [
      "zanoza"
      "beez"
      "nz"
      "mz"
    ];
    # Builders run in nix-daemon.service's cgroup, out of reach of the unit's
    # own limits, so bound them here: one derivation at a time on three of
    # beez's four cores.
    maxJobs = 1;
    buildCores = 3;
    cacheServer.enable = true;
    # Serve the candidate lock and per-host status for `sys adopt`.
    publish.enable = true;

    # Telegram notifications
    telegram = {
      enable = true;
      chatId = "681806836";
      # beez reaches api.telegram.org only through the router's SOCKS proxy,
      # the same one its other notifiers use.
      proxyUrl = "socks5h://192.168.89.207:20170";
      notifyOnSuccess = true;
      notifyOnPartialSuccess = true;
      notifyOnFailure = true;
      successPriority = "low"; # Silent for full success
      failurePriority = "high"; # Sound for any failures
    };

    # Email fallback when Telegram delivery fails
    email = {
      enable = true;
      recipient = "bulavintsev.sergey@gmail.com";
    };
  };

  services.nix-remote-builder.client.enable = false;

  system.nix.cache-servers = [
    {
      url = "http://beez.sbulav.ru:5000";
      key = "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8=";
      priority = 10;
    }
  ];

  # Email service for notifications
  custom.containers.msmtp = {
    enable = true;
    secret_file = "secrets/beez/default.yaml";
  };

  custom.security.sops = {
    enable = true;
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/beez/default.yaml";
  };

  users.users.sab.openssh.authorizedKeys.keys = [
    # zanoza's root-run OpenCloud restic job: sftp only, nothing else.
    "restrict,command=\"internal-sftp\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIMvhXdwuj2DKXZBFC+1UeqJU3h3T0noFtgmB0Mrjdr restic-opencloud@zanoza"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDH2vxB14+ZGFFgtQ6UQ6zw33r/4e/vkMIzNKeaTnDRHmmfnjDSU5oXWt7OSCZQw8zPSbzPV7QPKC9MwEdsl9ZXr4kVxAvN/d/oI/cBU/77tMDW/m1d+SEqhztNrBfpSIavuCT+K9l1vMr/R4qoRxSfLRVsBhr3Xfk3bxZ2vh9dsefZXbL4/ebzW74RUoh1GccPqvBQJxP/+wYsyspn3lsmEi2AbIJprR6fN2Vb3pTW/D0E7k2iIcuBOd1hsw3mn5e2OpXOG2R0XcssBjlquS23up3sIujbw46gITIe1+kCLnmCfGXRDOmcUfB4ySwUlFma8RjcZg7vTGUe47PNJmo3 sab@fedoraz.sbulav.tk"
  ];

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  environment.systemPackages = with pkgs; [
    git
    nixd # LSP for nix
    smartmontools
    ntfs3g
    nvme-cli
  ];
  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "25.11";
  # ======================== DO NOT CHANGE THIS ========================
}
