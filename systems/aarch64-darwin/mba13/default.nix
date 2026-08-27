{ ... }:
{
  networking.hostName = "mba13";

  suites.common.enable = true;
  suites.develop.enable = true;

  custom.user.enable = true;
  custom.apps.obsidian.enable = true;
  custom.desktop.aerospace.enable = true;

  # Let the central herdr-remote relay on zanoza poll this laptop (DHCP may
  # hand out 192.168.92.136 or the older 192.168.92.143) while it is online.
  services.openssh.enable = true;

  # Reap SSH sessions whose peer vanished without a FIN. macOS launchd caps
  # concurrent sshd instances at 42 (inetdCompatibility.Instances in
  # /System/Library/LaunchDaemons/ssh.plist); past that it accepts each new
  # connection and closes it before the banner, so the laptop goes completely
  # unreachable — even from localhost. Every relay poll that dies with the lid
  # (sleep, Wi-Fi change, VPN flap) strands one session, and sshd defaults to
  # ClientAliveInterval 0, i.e. it never notices. A day of that fills all 42.
  #
  # 300 x 6 = 30 minutes of an unanswered probe before a session is dropped.
  # This never touches a working session, however long it runs: the probe is
  # answered by the SSH layer itself, so a busy or idle-but-connected agent
  # replies without doing anything. Only a genuinely dead peer stays silent.
  # 30 minutes still clears strays far faster than they can accumulate to 42.
  services.openssh.extraConfig = ''
    ClientAliveInterval 300
    ClientAliveCountMax 6
  '';

  # Always resolve the home lab (beez, zanoza, *.sbulav.ru) via AdGuard,
  # on and off the corporate VPN — macOS equivalent of the Linux split DNS.
  custom.networking.split-dns = {
    enable = true;
    resolvers."sbulav.ru" = [ "172.16.64.104" ];
    hosts = {
      # The arr UIs (issue #39) are pinned here, not just left to the
      # resolver above: their traefik routers are LAN-only
      # (ClientIP 192.168.80.0/20), so a browser that answers the name from
      # public DNS gets the router's WAN address, hairpins out to the ISP and
      # arrives from a public source IP — no router matches and traefik
      # returns 404. Firefox defaults network.trr.exclude-etc-hosts=true, so
      # an /etc/hosts entry is consulted before DoH; it also survives the
      # corporate VPN capturing DNS, which 172.16.64.104 does not.
      "192.168.89.207" = [
        "zanoza"
        "zanoza.sbulav.ru"
        "sonarr.sbulav.ru"
        "radarr.sbulav.ru"
        "prowlarr.sbulav.ru"
        "qbittorrent.sbulav.ru"
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
  };

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = 7;
  # ======================== DO NOT CHANGE THIS ========================
}
