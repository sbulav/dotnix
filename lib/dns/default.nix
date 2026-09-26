# Household DNS data only: both resolvers publish the same split-DNS answers.
#
# Every module and host that needs one of these addresses reads it from here;
# the `household-dns` check asserts the AdGuard containers actually serve the
# resolver addresses advertised below.
{ lib, ... }:
let
  hosts = {
    zanoza = "192.168.89.207";
    beez = "192.168.92.194";
    mz = "192.168.89.200";
  };
  # The address each host's resolver is reached at: zanoza's AdGuard container
  # is routed directly (the router routes 172.16.64.0/18 to zanoza), beez's is
  # port-forwarded from its LAN address.
  resolverAddresses = {
    zanoza = "172.16.64.104";
    beez = hosts.beez;
  };
  resolvers = [
    resolverAddresses.zanoza
    resolverAddresses.beez
  ];
  # Traefik and Authelia live on zanoza; every published service name resolves
  # there, whichever host runs the backend. Grafana is the exception: beez
  # publishes it with its own Traefik so dashboards stay reachable while
  # zanoza or the work site is down (see `beezIngressNames`).
  ingress = hosts.zanoza;
  ingressNames = [
    "authelia"
    "flood"
    "herdr"
    "herdr-relay"
    "home"
    "immich"
    "jellyfin"
    "opencloud"
    "prometheus"
    "prowlarr"
    "qbittorrent"
    "radarr"
    "sing-box"
    "sonarr"
    "traefik"
  ];
  beezIngressNames = [ "grafana" ];
in
{
  dns = {
    inherit
      hosts
      resolverAddresses
      resolvers
      ingress
      ;
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
      ++ (map (name: {
        hostname = "${name}.sbulav.ru";
        ip = hosts.beez;
      }) beezIngressNames)
      ++
        lib.concatMap
          (name: [
            {
              hostname = name;
              ip = hosts.${name};
            }
            {
              hostname = "${name}.sbulav.ru";
              ip = hosts.${name};
            }
          ])
          [
            "beez"
            "mz"
          ];
  };
}
