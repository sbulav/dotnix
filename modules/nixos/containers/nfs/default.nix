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
in {
  options.${namespace}.containers.nfs = with types; {
    enable = mkBoolOpt false "Enable NFS server for exporting filesystems";
    filesystems = mkOpt (listOf str) [] "List of filesystems to export, in the format ['/path/to/dir']";
    restrictedClients = mkOpt (listOf str) ["192.168.88.0/23"] "List of allowed client IPs for NFS exports";
  };

  config = mkIf cfg.enable {
    # NFS server configuration
    services.nfs.server = {
      enable = true;

      # For each entry in filesystems map <fs> <client>(options)
      exports = lib.concatStringsSep "\n" (map (fs: lib.concatStringsSep "\n" (map (client: "${fs} ${client}(rw,sync,no_subtree_check,insecure)") cfg.restrictedClients)) cfg.filesystems);
    };

    # Optionally, enable firewall for NFS
    networking.firewall.allowedTCPPorts = [2049]; # NFS uses port 2049
    networking.firewall.allowedUDPPorts = [2049];
  };
}
