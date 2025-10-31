{ lib, ... }:
with lib.custom;
{
  custom = {
    suites = {
      common = enabled;
      develop = enabled;
    };

    virtualisation = {
      virt-manager = disabled;
    };

    security = {
      sops = {
        enable = true; # sops-nix Darwin compatibility issue resolved
        sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        defaultSopsFile = lib.snowfall.fs.get-file "secrets/mbp16/default.yaml";

        # System SSH key using template (moved from deprecated system module)
        secrets = {
          "mbp16_sab_ssh_key" = lib.custom.secrets.system.sshKey "mbp16_sab" "mbp16" // {
            owner = "sab";
            sopsFile = lib.snowfall.fs.get-file "secrets/mbp16/default.yaml";
          };
        };
      };
    };

    desktop.aerospace = enabled;

    desktop.stylix = {
      enable = true;
      theme = "cyberdream";
    };
  };

  # suites.common.enable = true; # Enables the basics, like audio, networking, ssh, etc.
  environment.systemPath = [
    "/opt/homebrew/bin"
  ];

  system = {
    primaryUser = "sab";
    stateVersion = 4;
  };
}
