{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.network-tuning;
in
{
  options.system.network-tuning = {
    enable = mkBoolOpt false "Whether to enable network sysctl hardening and TCP tuning";
    optimizeTcp = mkBoolOpt true "Whether to enable BBR congestion control and TCP buffer tuning";
  };

  config = mkIf cfg.enable {
    # net.ipv4.ip_forward is intentionally NOT set here — the transparent
    # proxy module owns it on hosts that route. No net.ipv6.* — IPv6 is
    # disabled at the kernel level fleet-wide.
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = mkDefault 1;
      "net.ipv4.conf.default.rp_filter" = mkDefault 1;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
      # Upstream sets this mkDefault "1" (string); int at normal priority wins.
      "net.ipv4.tcp_syncookies" = 1;
      "net.ipv4.tcp_rfc1337" = 1;
    }
    // optionalAttrs cfg.optimizeTcp {
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_mtu_probing" = mkDefault 1;
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_rmem" = "4096 1048576 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    };

    boot.kernelModules = optionals cfg.optimizeTcp [ "tcp_bbr" ];
  };
}
