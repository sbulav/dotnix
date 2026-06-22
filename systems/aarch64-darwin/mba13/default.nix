{ ... }:
{
  networking.hostName = "mba13";

  suites.common.enable = true;
  suites.develop.enable = true;

  custom.user.enable = true;
  custom.apps.obsidian.enable = true;
  custom.desktop.aerospace.enable = true;

  # Always resolve the home lab (beez, zanoza, *.sbulav.ru) via AdGuard,
  # on and off the corporate VPN — macOS equivalent of the Linux split DNS.
  custom.networking.split-dns = {
    enable = true;
    resolvers."sbulav.ru" = [ "172.16.64.104" ];
    hosts = {
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
  };

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = 7;
  # ======================== DO NOT CHANGE THIS ========================
}
