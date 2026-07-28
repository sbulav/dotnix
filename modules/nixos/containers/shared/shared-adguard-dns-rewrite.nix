# DNS rewrite module, by default pointing the host at AdGuard's rewriteAddress.
#
# The answer must be an *IP*, not a hostname. AdGuard applies a hostname answer as a
# CNAME and only resolves that target against its own rewrites for A queries — AAAA
# queries are forwarded upstream, which returns the public chain
# (adguard.<domain> -> <router DDNS name> -> WAN IP). systemd-resolved inside a
# container then serves that public address, and connecting to the router's own WAN IP
# from the routed container subnet fails (no NAT hairpin), so containers could not reach
# services on this host. A direct-IP rewrite is applied to A and returns NODATA for
# AAAA, so nothing leaks upstream.
{
  host ? "test.sbulav.ru",
  url ? null,
  rewrite_enabled ? false,
  ...
}:
{
  config,
  lib,
  namespace,
  ...
}:
let
  adguard = config.${namespace}.containers.adguard;
in
{
  config = lib.mkIf (rewrite_enabled && adguard.enable) {
    containers.adguard.config.services.adguardhome.settings.filtering = {
      rewrites = [
        {
          domain = host;
          answer = if url != null then url else adguard.rewriteAddress;
          enabled = true;
        }
      ];
    };
  };
}
