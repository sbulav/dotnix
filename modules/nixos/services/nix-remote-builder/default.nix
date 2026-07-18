{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.services.nix-remote-builder;
  clientCfg = cfg.client;
  serverCfg = cfg.server;
in
{
  options.services.nix-remote-builder = with types; {
    client = {
      enable = mkBoolOpt false "Use a constrained remote Nix builder over SSH";

      hostName = mkOpt str "zanoza" "Host name or address of the remote Nix builder";

      system = mkOpt str "x86_64-linux" "System type supported by the remote builder";

      sshUser = mkOpt str "nix-builder" "Restricted SSH user on the remote builder";

      sshKeySecret =
        mkOpt str "nix-remote-builder-ssh-key"
          "SOPS secret containing the client's passphrase-free SSH private key";

      publicHostKey =
        mkOpt (nullOr str) null
          "Base64-encoded SSH host public key used to pin the remote builder";

      maxJobs = mkOpt int 2 "Maximum number of jobs scheduled on the remote builder";

      speedFactor = mkOpt int 4 "Remote builder speed relative to the local machine";

      supportedFeatures = mkOpt (listOf str) [
        "big-parallel"
      ] "Nix system features advertised by the remote builder";
    };

    server = {
      enable = mkBoolOpt false "Accept constrained remote Nix builds over SSH";

      user = mkOpt str "nix-builder" "Restricted account used by the remote build client";

      authorizedKey = mkOpt (nullOr str) null "SSH public key authorized for the remote build client";

      allowedSource =
        mkOpt str "192.168.92.194"
          "Source address allowed to use the remote builder SSH key";

      maxJobs = mkOpt int 2 "Maximum number of concurrent Nix builds on this host";

      cores = mkOpt int 2 "CPU cores made available to each Nix build job";

      cpuQuota = mkOpt str "400%" "Hard CPU quota for the Nix daemon cgroup";

      memoryHigh = mkOpt str "8G" "Memory pressure threshold for the Nix daemon cgroup";

      memoryMax = mkOpt str "10G" "Hard memory limit for the Nix daemon cgroup";

      memorySwapMax = mkOpt str "2G" "Hard swap limit for the Nix daemon cgroup";

      cpuWeight = mkOpt int 20 "Relative CPU weight for Nix builds";

      ioWeight = mkOpt int 10 "Relative I/O weight for Nix builds";
    };
  };

  config = mkMerge [
    (mkIf clientCfg.enable {
      assertions = [
        {
          assertion = clientCfg.publicHostKey != null && clientCfg.publicHostKey != "";
          message = "services.nix-remote-builder.client.publicHostKey must pin the builder's SSH host key";
        }
      ];

      sops.secrets.${clientCfg.sshKeySecret} = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      nix = {
        distributedBuilds = true;
        buildMachines = [
          {
            hostName = clientCfg.hostName;
            protocol = "ssh-ng";
            system = clientCfg.system;
            sshUser = clientCfg.sshUser;
            sshKey = config.sops.secrets.${clientCfg.sshKeySecret}.path;
            inherit (clientCfg)
              maxJobs
              speedFactor
              supportedFeatures
              publicHostKey
              ;
          }
        ];

        settings = {
          builders-use-substitutes = true;
          fallback = true;
        };
      };
    })

    (mkIf serverCfg.enable {
      assertions = [
        {
          assertion = serverCfg.authorizedKey != null && serverCfg.authorizedKey != "";
          message = "services.nix-remote-builder.server.authorizedKey must contain the client's SSH public key";
        }
        {
          assertion = serverCfg.allowedSource != "";
          message = "services.nix-remote-builder.server.allowedSource must restrict the client source address";
        }
        {
          assertion = serverCfg.maxJobs > 0 && serverCfg.cores > 0;
          message = "services.nix-remote-builder.server maxJobs and cores must be positive";
        }
      ];

      users.groups.${serverCfg.user} = { };
      users.users.${serverCfg.user} = {
        description = "Restricted Nix remote builder";
        isSystemUser = true;
        group = serverCfg.user;
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = [
          ''restrict,from="${serverCfg.allowedSource}",command="${config.nix.package}/bin/nix-daemon --stdio" ${serverCfg.authorizedKey}''
        ];
      };

      nix = {
        daemonCPUSchedPolicy = "batch";
        daemonIOSchedClass = "idle";
        daemonIOSchedPriority = 7;
        settings = {
          allowed-users = [ serverCfg.user ];
          trusted-users = [ serverCfg.user ];
          max-jobs = serverCfg.maxJobs;
          cores = serverCfg.cores;
        };
      };

      systemd.services.nix-daemon.serviceConfig = {
        CPUQuota = serverCfg.cpuQuota;
        CPUWeight = serverCfg.cpuWeight;
        IOWeight = serverCfg.ioWeight;
        MemoryHigh = serverCfg.memoryHigh;
        MemoryMax = serverCfg.memoryMax;
        MemorySwapMax = serverCfg.memorySwapMax;
        Nice = 10;
        OOMScoreAdjust = 500;
        TasksMax = 512;
      };
    })
  ];
}
