# DNS client configuration for containers to use AdGuard DNS
# This module configures containers to use AdGuard as their DNS server
# instead of inheriting the host's DNS configuration
{
  lib,
  container_name,
  adguard_ip ? "172.16.64.104",
  use_adguard_dns ? false,
  fallback_dns ? [
    "1.1.1.1"
    "1.0.0.1"
  ],
  ...
}:
{
  config,
  ...
}:
{
  config = lib.mkIf use_adguard_dns {
    containers.${container_name}.config = {
      networking = {
        # Don't use host's resolv.conf
        useHostResolvConf = lib.mkForce false;
        # Set AdGuard as primary DNS with optional fallbacks
        nameservers = [ adguard_ip ] ++ fallback_dns;
      };
      # Disable systemd-resolved in container
      services.resolved.enable = false;
    };
  };
}
