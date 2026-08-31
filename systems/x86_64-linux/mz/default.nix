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
    battery.enable = false; # Only for laptops, they will still work without it, just improves battery life
    sleep = {
      enable = true;
      gvfsUnmountFix.enable = true;
      audioResumeFix.enable = true;
    };

    nix.cache-servers = [
      {
        url = "http://beez.sbulav.ru:5000";
        key = "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8=";
        priority = 10;
      }
      # Official noctalia cache (issue #37 shell trial) — the flake input pins
      # the upstream `cachix` branch, so builds should always hit this.
      {
        url = "https://noctalia.cachix.org";
        key = "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=";
        priority = 12;
      }
    ];
  };
  hardware = {
    bluetooth.enable = true;
    bluetoothmy.enable = true;
    cpu.amd.enable = true;
    fingerprint.enable = false;
    gpu.intel.enable = false;
    gpu.nvidia.enable = true;
    openglmy.enable = true;
    rgb.openrgb.enable = true;
    yubikey = {
      enable = true;
      smartcard.enable = true;
    };
    scanning.enable = false;
    # XBOX Wireless controller
    xone.enable = true;
    xpadneo.enable = false;
  };

  environment.systemPackages = with pkgs; [
    # herdr-relay browses this host's project roots by running a python3
    # helper over non-interactive SSH; without python3 on the system PATH
    # every browse of this host fails as "Folder is unavailable".
    python3
  ];

  # Direct KMS capture needs the capability-wrapped gsr-kms-server supplied
  # by NixOS. Without it gpu-screen-recorder falls back to pkexec and asks for
  # the root password every time a recording starts.
  programs.gpu-screen-recorder.enable = true;

  # Suites managed by nix, see suites by home-manager in homes
  suites = {
    common.enable = true; # Enables the basics, like audio, networking, ssh, etc.
    desktop.enable = true;
    develop.enable = true;
    games.enable = true;
  };
  custom = {
    security.sops = {
      enable = true;
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      defaultSopsFile = lib.snowfall.fs.get-file "secrets/mz/default.yaml";
    };

    virtualisation = {
      virt-manager.enable = true;
      kvm.enable = false;
      podman.enable = false;
    };

    # Enable for printing, configure on http://localhost:631/printers/Pantum_M6550NW_series
    services.avahi.enable = true;
    services.printing.enable = true;

    services.prometheus-exporters = {
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
  };
  # Split DNS for the home lab: force *.sbulav.ru to the home AdGuard
  # (172.16.64.104) whenever we are on the home LAN, even when a corporate
  # VPN injects its own DNS servers. Otherwise sbulav.ru resolves to the
  # router's public IP instead of the LAN address behind it.
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

  # Disable gnome keyring own agents, as we use SSH via GPG-agent
  systemd.user.sockets."gcr-ssh-agent".enable = false;
  systemd.user.services."gcr-ssh-agent".enable = false;
  # Allow control of lian li galahad II
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0416", ATTR{idProduct}=="7395", MODE="0666", GROUP="users"
  '';

  # The noctalia lockscreen authenticates against the `login` PAM stack,
  # which NixOS ships with nullok on pam_unix. sab's password is imperative
  # state (mutableUsers), so if it were ever cleared a bare Enter would
  # unlock the screen with no YubiKey. The old swaylock stack had no nullok;
  # keep that property. TTY logins with a set password are unaffected.
  # (mkForce: nixpkgs' pam module sets true for login unconditionally.)
  security.pam.services.login.allowNullPassword = lib.mkForce false;

  # Authorize zanoza's herdr-relay key so the relay can poll herdr on mz over
  # SSH non-interactively (BatchMode, no agent → uses zanoza:~/.ssh/id_ed25519).
  users.users.sab.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPhz1eq3urXjH/zUC4xdcwurGlpVml0fcisxJwx25aRE sab@zanoza"
  ];

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "25.11";
  # ======================== DO NOT CHANGE THIS ========================
}
