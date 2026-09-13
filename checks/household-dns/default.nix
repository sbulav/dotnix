{ lib, runCommand, ... }:
let
  # Exercise the actual AdGuard module with only unrelated NixOS option groups
  # stubbed. Nested container settings remain the production module's output.
  evaluate =
    overrides:
    (lib.evalModules {
      specialArgs = {
        namespace = "custom";
        inherit lib;
      };
      modules = [
        ../../modules/nixos/containers/adguard
        ({ lib, ... }: {
          options = {
            networking = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            services = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            containers = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            custom.containers.traefik.routes = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
          };
          config.custom.containers.adguard = {
            enable = true;
            hostMappings = lib.custom.dns.hostMappings;
          }
          // overrides;
        })
      ];
    }).config;
  zanoza = evaluate { };
  beez = evaluate {
    publishWeb = false;
    externalInterface = "enp1s0";
    hostAddress = "172.16.65.10";
    localAddress = "172.16.65.104";
    listenAddress = "192.168.92.194";
  };
  z = (zanoza.containers.adguard.config { }).services.adguardhome;
  b = (beez.containers.adguard.config { }).services.adguardhome;
  records = z.settings.filtering.rewrites;
  answer = name: (builtins.head (builtins.filter (r: r.domain == name) records)).answer;
  domains = map (r: r.domain) records;
  resolved = lib.custom.dns.resolvedSettings;
in
assert z.settings.filtering == b.settings.filtering;
assert z.settings.filters == b.settings.filters;
assert z.settings.dns.upstream_dns == b.settings.dns.upstream_dns;
assert
  z.settings.dns.bootstrap_dns == [
    "1.1.1.2"
    "1.0.0.2"
  ];
assert !z.settings.dns.use_private_ptr_resolvers;
assert !z.mutableSettings && !b.mutableSettings;
assert builtins.length domains == builtins.length (lib.unique domains);
assert answer "home.sbulav.ru" == "192.168.89.207";
assert answer "prometheus.sbulav.ru" == "192.168.89.207";
assert answer "loki.sbulav.ru" == "192.168.89.207";
assert answer "beez.sbulav.ru" == "192.168.92.194";
assert resolved.DNS == "172.16.64.104 192.168.92.194" && resolved.FallbackDNS == "";
assert
  zanoza.networking.nameservers == [
    "172.16.64.104"
    "192.168.92.194"
  ];
assert
  beez.networking.nameservers == [
    "172.16.65.104"
    "172.16.64.104"
  ];
assert beez.networking.resolvconf.extraConfig == "allow_keys='static'";
assert beez.custom.containers.traefik.routes == { };
assert beez.networking.nat.externalInterface == "enp1s0";
assert beez.networking.nat.externalIP == "192.168.92.194";
assert
  beez.networking.nat.forwardPorts == [
    {
      proto = "tcp";
      sourcePort = 53;
      loopbackIPs = [ "192.168.92.194" ];
      destination = "172.16.65.104:53";
    }
    {
      proto = "udp";
      sourcePort = 53;
      loopbackIPs = [ "192.168.92.194" ];
      destination = "172.16.65.104:53";
    }
  ];
assert
  (beez.containers.adguard.config { }).networking.nameservers == [
    "1.1.1.2"
    "1.0.0.2"
  ];
runCommand "household-dns-check" { } ''
  touch "$out"
''
