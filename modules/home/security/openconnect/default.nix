{
  namespace,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.security.openconnect;

  # Internal nameservers and the domains that must resolve through them while
  # the VPN is up. Shared between the Linux (systemd-resolved) and Darwin
  # (/etc/resolver) split-DNS implementations.
  splitDnsServers = [
    "94.124.205.83"
    "94.124.204.83"
  ];
  splitDnsDomains = [
    "pyn.ru"
    "hh.ru"
    "hhdev.ru"
  ];

  # Linux: configure split DNS on the tun0 interface via systemd-resolved.
  configureResolvedSplitDns = ''
    if sudo ${pkgs.systemd}/bin/systemctl -q is-active systemd-resolved.service && ${pkgs.iproute2}/bin/ip link show tun0 >/dev/null 2>&1; then
      sudo ${pkgs.systemd}/bin/resolvectl dns tun0 ${toString splitDnsServers} || true
      sudo ${pkgs.systemd}/bin/resolvectl domain tun0 ${
        concatMapStringsSep " " (d: "'~${d}'") splitDnsDomains
      } || true
      sudo ${pkgs.systemd}/bin/resolvectl default-route tun0 no || true
      sudo ${pkgs.systemd}/bin/resolvectl flush-caches || true
    fi
  '';

  # Darwin: macOS resolves per-domain via /etc/resolver/<domain> files. Point
  # the internal domains at the VPN nameservers, then flush the resolver cache.
  darwinSetupSplitDns = ''
    for domain in ${toString splitDnsDomains}; do
      sudo mkdir -p /etc/resolver
      : | sudo tee /etc/resolver/$domain >/dev/null
      ${concatMapStringsSep "\n      " (
        s: "echo 'nameserver ${s}' | sudo tee -a /etc/resolver/$domain >/dev/null"
      ) splitDnsServers}
    done
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
  '';

  darwinTeardownSplitDns = ''
    for domain in ${toString splitDnsDomains}; do
      sudo rm -f /etc/resolver/$domain
    done
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
  '';

  route_delete_command =
    if pkgs.stdenv.isLinux then
      ''
        sudo ip route del 192.168.0.0/16
        sudo ip route add 10.8.0.1/32 via 192.168.90.1 #openconnect
        ${configureResolvedSplitDns}
      ''
    else if pkgs.stdenv.isDarwin then
      ''
        sudo route delete -net 192.168.0.0/16
        sudo route add -net 10.8.0.1/32 192.168.89.1 #openconnect
        ${darwinSetupSplitDns}
      ''
    else
      "";

  dns_teardown_command = if pkgs.stdenv.isDarwin then darwinTeardownSplitDns else "";

  vpnScript = pkgs.writeScriptBin "myvpn" ''
    #! ${pkgs.bash}/bin/sh

    function openconnecthelp ()
    {
      echo "******************************************************"
      echo "VPN access via openconnect"
      echo "******************************************************"
      echo
      echo "Usage: myvpn <up|down|status>"
    }

    if [ "$#" != "1" ]
    then
      openconnecthelp
      exit 0
    fi

    # Parse command
    case "$1" in
      up)
      ;;
      down)
      ;;
      status)
      ;;
      *)
        echo "ERROR: Invalid command <$1>"
        RESULT=2
      ;;
    esac
        # Parse command
        case "$1" in
          up)
            echo $OPENCONNECT_PW | \
              sudo ${pkgs.openconnect}/bin/openconnect --no-dtls --background \
              --passwd-on-stdin -u $OPENCONNECT_USER $OPENCONNECT_SERVER
            if [[ $? -ne 0 ]]; then
            echo "******************************************************"
              echo "ERROR: Cannot start VPN connection."
            else
              sleep 1
              echo "******************************************************"
              echo "My DNSs are:"
              grep "nameserver" /etc/resolv.conf
              echo "******************************************************"
              echo "VPN is up and running!"
              echo "******************************************************"
              echo "Removing LAN routes to VPN"
              ${route_delete_command}
            fi
          ;;
          down)
            echo "******************************************************"
            echo "Stopping the VPN and removing all routes"
            sudo kill -2 `pgrep openconnect`
            ${dns_teardown_command}
            echo "VPN stopped!"
          ;;
          status)
            echo "*******************STATUS*****************************"
            echo "Connected as $OPENCONNECT_USER to $OPENCONNECT_SERVER"
            echo "******************************************************"
            echo "Pid of openconnect are:"
            pgrep -l openconnect
            echo "******************************************************"
            echo "My DNSs are:"
            grep "nameserver" /etc/resolv.conf
          ;;
        esac

  '';
in
{
  options.custom.security.openconnect = with types; {
    enable = mkBoolOpt false "Whether or not to install openconnect and add script.";
  };

  config = mkIf cfg.enable {
    # sops.secrets = lib.mkIf config.${namespace}.security.sops.enable {
    #   openconnect_pw = {
    #     sopsFile = lib.snowfall.fs.get-file "secrets/${config.${namespace}.user.name}/default.yaml";
    #   };
    # };
    home.packages = with pkgs; [
      openconnect
      vpnScript
    ];
  };
}
