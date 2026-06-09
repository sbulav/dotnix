{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.stdenv.hostPlatform.system}.full;
  homeLabSplitDnsScript = pkgs.writeShellScript "home-lab-split-dns" ''
    set -eu

    apply_iface() {
      iface="$1"

      if [ -z "$iface" ]; then
        return 0
      fi

      addresses="$(${pkgs.iproute2}/bin/ip -o -4 addr show dev "$iface" 2>/dev/null || true)"

      case "$addresses" in
        *" inet 192.168.8"[0-9].*|*" inet 192.168.9"[0-5].*)
          ${pkgs.systemd}/bin/resolvectl dns "$iface" 172.16.64.104 || true
          ${pkgs.systemd}/bin/resolvectl domain "$iface" '~sbulav.ru' sbulav.ru || true
          ${pkgs.systemd}/bin/resolvectl default-route "$iface" no || true
          ${pkgs.systemd}/bin/resolvectl flush-caches || true
          ;;
      esac
    }

    if ! ${pkgs.systemd}/bin/resolvectl status >/dev/null 2>&1; then
      exit 0
    fi

    if [ "$#" -gt 0 ]; then
      iface="$1"
      event="''${2:-}"

      case "$event" in
        up|dhcp4-change|connectivity-change) ;;
        *) exit 0 ;;
      esac

      apply_iface "$iface"
      exit 0
    fi

    while IFS= read -r line; do
      set -- $line
      apply_iface "''${2%:}"
    done < <(${pkgs.iproute2}/bin/ip -o -4 addr show)
  '';
in
{
  imports = [ ./hardware-configuration.nix ];
  system = {
    wallpaper = "${wallpapers}/share/wallpapers/unorganized/vu_meter_code_neon.png";
    # Enable Bootloader
    boot.efi.enable = true;
    battery.enable = true; # Only for laptops, they will still work without it, just improves battery life
    laptopProfile.enable = true;
    sleep = {
      enable = true;
      gvfsUnmountFix.enable = true;
    };

    nix.cache-servers = [
      {
        url = "http://beez.sbulav.ru:5000";
        key = "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8=";
        priority = 10;
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
  networking.search = lib.mkForce [ ];

  networking.networkmanager = {
    dns = "systemd-resolved";
    dispatcherScripts = [
      {
        source = homeLabSplitDnsScript;
        type = "basic";
      }
    ];
  };

  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNS = "1.1.1.1 1.0.0.1 8.8.8.8";
      DNSSEC = "false";
      FallbackDNS = [
        "1.1.1.1"
        "1.0.0.1"
        "8.8.8.8"
      ];
    };
  };

  systemd.services = {
    home-lab-split-dns = {
      description = "Apply split DNS for home lab domains";
      after = [
        "NetworkManager.service"
        "systemd-resolved.service"
      ];
      wants = [
        "NetworkManager.service"
        "systemd-resolved.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${homeLabSplitDnsScript}";
      };
    };

    systemd-resolved.postStart = "${homeLabSplitDnsScript}";
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
