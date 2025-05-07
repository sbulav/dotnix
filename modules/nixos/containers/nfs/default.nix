{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.nfs;
  anonUid = 65534; # nobody
  anonGid = 65534; # nogroup
in {
  options.${namespace}.containers.nfs = with lib.types; {
    enable = mkBoolOpt false "Enable NFS server for exporting filesystems";
    filesystems = mkOpt (listOf str) [] "List of filesystems to export, in the format ['/path/to/dir']";
    restrictedClients = mkOpt (listOf str) ["192.168.80.0/20"] "List of allowed client IPs for NFS exports";
  };

  config = mkIf cfg.enable {
    services.nfs.server.enable = true;

    # Build the exports lines.  If fs == "/tank/ipcam" → everybody as anonymous;
    # otherwise use your restrictedClients.
    services.nfs.server.exports = lib.concatStringsSep "\n" (
      map (
        fs: let
          isIpcam = fs == "/tank/ipcam";
          clients =
            if isIpcam
            then ["*"]
            else cfg.restrictedClients;
          extraOpts =
            if isIpcam
            then "all_squash,anonuid=${toString anonUid},anongid=${toString anonGid}"
            else "";
        in
          lib.concatStringsSep "\n" (
            map (
              client:
              # <path> <client>(rw,sync,no_subtree_check,insecure{,all_squash,...})
              "${fs} ${client}(rw,sync,no_subtree_check,insecure${
                if extraOpts != ""
                then "," + extraOpts
                else ""
              })"
            )
            clients
          )
      )
      cfg.filesystems
    );

    # Listen on UDP for NFS‑RPC
    services.nfs.settings.nfsd.udp = "y";

    # Open the usual NFS ports
    networking.firewall.allowedTCPPorts = [111 2049 4000 4001 20048];
    networking.firewall.allowedUDPPorts = [111 2049 4000 4001 20048];
  };
}
