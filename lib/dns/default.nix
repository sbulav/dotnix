# Household DNS data only: both resolvers publish the same split-DNS answers.
{ lib, ... }:
let
  resolvers = [
    "172.16.64.104"
    "192.168.92.194"
  ];
  ingress = "192.168.89.207";
  ingressNames = [
    "authelia"
    "flood"
    "grafana"
    "herdr"
    "herdr-relay"
    "home"
    "immich"
    "jellyfin"
    "opencloud"
    "prometheus"
    "loki"
    "prowlarr"
    "qbittorrent"
    "radarr"
    "sing-box"
    "sonarr"
    "traefik"
  ];
in
{
  dns = {
    inherit resolvers;
    resolvedSettings = {
      DNS = lib.concatStringsSep " " resolvers;
      FallbackDNS = "";
      Domains = "~.";
    };
    hostMappings =
      (map (name: {
        hostname = "${name}.sbulav.ru";
        ip = ingress;
      }) ingressNames)
      ++ [
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
}
