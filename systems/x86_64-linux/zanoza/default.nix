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
  tvProxyAssets = pkgs.symlinkJoin {
    name = "tv-proxy-xray-assets";
    paths = [
      pkgs.v2ray-geoip
      pkgs.v2ray-domain-list-community
    ];
  };
  tvProxyRouterConfig = pkgs.writeText "tv-proxy-router.json" (
    builtins.toJSON {
      log.loglevel = "warning";
      inbounds = [
        {
          tag = "tv";
          listen = "127.0.0.1";
          port = 20169;
          protocol = "socks";
          settings.udp = false;
          sniffing = {
            enabled = true;
            destOverride = [
              "http"
              "tls"
            ];
            routeOnly = false;
          };
        }
      ];
      outbounds = [
        {
          tag = "proxy";
          protocol = "socks";
          settings.servers = [
            {
              address = "172.16.64.108";
              port = 20170;
            }
          ];
        }
        {
          tag = "direct";
          protocol = "freedom";
        }
      ];
      routing = {
        domainStrategy = "IPIfNonMatch";
        rules = [
          {
            type = "field";
            outboundTag = "direct";
            domain = [
              "domain:sbulav.ru"
              "domain:pyn.ru"
              "domain:hhdev.ru"
              "geosite:category-ru"
              "regexp:\\.ru$"
              "regexp:\\.su$"
              "regexp:\\.xn--p1ai$"
            ];
          }
          {
            type = "field";
            outboundTag = "direct";
            ip = [
              "geoip:private"
              "geoip:ru"
            ];
          }
          {
            type = "field";
            outboundTag = "proxy";
            network = "tcp";
          }
        ];
      };
    }
  );
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  hardware = {
    fingerprint.enable = false;
    cpu.amd.enable = true;
    openglmy.enable = true;
  };

  system = {
    nix.cache-servers = [
      {
        url = "http://beez.sbulav.ru:5000";
        key = "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8=";
        priority = 10;
      }
    ];
  };

  suites = {
    server.enable = true; # Enables the basics, like neovim, ssh, etc.
    desktop.enable = false;
    develop.enable = false;
  };

  custom.security.sops = {
    enable = true;
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/zanoza/default.yaml";
  };

  users.users.sab.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDH2vxB14+ZGFFgtQ6UQ6zw33r/4e/vkMIzNKeaTnDRHmmfnjDSU5oXWt7OSCZQw8zPSbzPV7QPKC9MwEdsl9ZXr4kVxAvN/d/oI/cBU/77tMDW/m1d+SEqhztNrBfpSIavuCT+K9l1vMr/R4qoRxSfLRVsBhr3Xfk3bxZ2vh9dsefZXbL4/ebzW74RUoh1GccPqvBQJxP/+wYsyspn3lsmEi2AbIJprR6fN2Vb3pTW/D0E7k2iIcuBOd1hsw3mn5e2OpXOG2R0XcssBjlquS23up3sIujbw46gITIe1+kCLnmCfGXRDOmcUfB4ySwUlFma8RjcZg7vTGUe47PNJmo3 sab@fedoraz.sbulav.tk"
  ];

  services.nix-remote-builder.server = {
    enable = true;
    allowedSource = "192.168.92.194";
    authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAvkkN80V8+tO5rc40e5xpk0IQMM83nvj/3mwsQh3tfG beez-zanoza-nix-builder";
  };

  # Keep sab's central herdr-remote relay and web app alive without a login.
  users.users.sab.linger = true;

  custom.virtualisation = {
    virt-manager.enable = false;
    kvm.enable = false;
    podman.enable = false;
  };

  custom.services = {
    ipcamCleanup.enable = true;
    ipcamJpegFix.enable = true;
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
    # Route-only: proxies to herdr-remote services running locally on zanoza.
    herdr-remote = {
      enable = true;
      host = "herdr.sbulav.ru";
      relayHost = "herdr-relay.sbulav.ru";
    };
    nextcloud = {
      enable = false;
      host = "nextcloud.sbulav.ru";
      secret_file = "secrets/zanoza/default.yaml";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.106";
    };
    jellyfin = {
      enable = true;
      enableGPU = true;
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
    };
    opencloud = {
      enable = true;
      host = "opencloud.sbulav.ru";
      hostAddress = "172.16.64.10";
      localAddress = "172.16.64.110";
      secret_file = "secrets/zanoza/default.yaml";
      # Personal-space UUID for `sab` — read from
      # /tank/opencloud/posix-storage/users/<uuid>/ after first OIDC login.
      userId = "05307840-a7bf-4448-8dc4-6a9ca7375cb9";
      externalMounts = {
        Video = "/tank/video";
        Downloads = "/tank/torrents/download";
      };
    }; # }}}
  };

  # Transparent proxy gateway for the Android TV (YouTube unblock):
  # the MikroTik policy-routes traffic from the TV here; TCP 80/443 is
  # redirected via redsocks into the v2rayA SOCKS5 (VLESS outbound).
  # Scoped by sourceIps so no other LAN host or local service is affected.
  custom.services.linuxTransparentProxy = {
    enable = true;
    mode = "redirect";
    interface = "enp3s0";
    # A local Xray router keeps Russian services direct and sends all other
    # traffic through v2rayA while preserving redsocks' SOCKS5 transport.
    v2rayAHost = "127.0.0.1";
    v2rayAPort = 20169;
    # 12345 (module default) is taken by Grafana Alloy's HTTP listener
    listenPort = 12346;
    tcpPorts = [
      80
      443
    ];
    sourceIps = [
      "192.168.89.248" # phillips 58pus (Android TV)
    ];
  };

  systemd.services = {
    tv-proxy-router = {
      description = "Route TV traffic between direct and v2rayA outbounds";
      wantedBy = [ "multi-user.target" ];
      after = [ "container@v2raya.service" ];
      requires = [ "container@v2raya.service" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.xray} run -c ${tvProxyRouterConfig}";
        Restart = "on-failure";
        RestartSec = "2s";
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
      environment.XRAY_LOCATION_ASSET = "${tvProxyAssets}/share/v2ray";
    };
    redsocks = {
      after = [ "tv-proxy-router.service" ];
      requires = [ "tv-proxy-router.service" ];
    };
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
