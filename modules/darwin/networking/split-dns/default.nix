{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.networking.split-dns;

  resolverEntries = mapAttrs' (
    domain: servers:
    nameValuePair "resolver/${domain}" {
      text = concatMapStringsSep "\n" (s: "nameserver ${s}") servers + "\n";
    }
  ) cfg.resolvers;

  # nix-darwin refuses to let `environment.etc` own /etc/hosts: its networking
  # activation restores the original file from the .before-nix-darwin backup on
  # every switch. So instead we append an idempotent, marker-delimited block to
  # the real /etc/hosts during activation.
  beginMarker = "# >>> custom.networking.split-dns (managed) >>>";
  endMarker = "# <<< custom.networking.split-dns (managed) <<<";
  hostsBlock = concatStringsSep "\n" (
    [ beginMarker ]
    ++ mapAttrsToList (ip: names: "${ip}\t${concatStringsSep " " names}") cfg.hosts
    ++ [ endMarker ]
  );
in
{
  options.custom.networking.split-dns = with types; {
    enable = mkBoolOpt false "Whether to enable persistent split DNS and static host entries.";

    resolvers = mkOpt (attrsOf (listOf str)) { } ''
      Map of DNS domain to the list of nameserver IPs that should always
      resolve it. Each entry becomes an /etc/resolver/<domain> file, which
      macOS consults ahead of the default (and VPN-pushed) resolvers, so the
      domain resolves both on and off the VPN. Mirrors the Linux home-lab
      systemd-resolved split DNS (`resolvectl domain ~<domain>`).
    '';

    hosts = mkOpt (attrsOf (listOf str)) { } ''
      Static host entries, keyed by IP address with a list of names (short
      and/or FQDN). Appended as a managed block to /etc/hosts on activation
      (nix-darwin has no `networking.hosts` and reverts `environment.etc`
      management of /etc/hosts). Needed so bare short names (e.g. `beez`)
      resolve, which /etc/resolver cannot do.
    '';
  };

  config = mkIf cfg.enable (mkMerge [
    { environment.etc = resolverEntries; }

    (mkIf (cfg.hosts != { }) {
      system.activationScripts.extraActivation.text = ''
        echo "applying custom.networking.split-dns host entries to /etc/hosts..." >&2
        touch /etc/hosts
        # Drop any previously-managed block.
        ${pkgs.gnused}/bin/sed -i -e '/^${beginMarker}$/,/^${endMarker}$/d' /etc/hosts
        # Trim trailing blank lines so the block is re-appended cleanly.
        ${pkgs.gnused}/bin/sed -i -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' /etc/hosts
        # Append a fresh managed block.
        cat >> /etc/hosts <<'NIX_SPLIT_DNS_EOF'

        ${hostsBlock}
        NIX_SPLIT_DNS_EOF
      '';
    })
  ]);
}
