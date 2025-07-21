{
  lib,
  inputs,
  namespace,
}: let
  inherit (inputs) deploy-rs;

  # Helper: Returns true if a system is a Darwin system (MacOS)
  isDarwin = system:
    lib.hasPrefix "aarch64-darwin" system || lib.hasPrefix "x86_64-darwin" system;

  mkDeploy = {
    self,
    overrides ? {},
  }: let
    hosts = self.nixosConfigurations or {};
    names = builtins.attrNames hosts;
    nodes =
      lib.foldl (
        result: name: let
          host = hosts.${name};
          user = host.config.${namespace}.user.name or null;
          system = host.pkgs.system;
          override = overrides.${name} or {};
          # Only inject checks = false for Darwin systems
          checksOpt =
            if isDarwin system
            then {checks = false;}
            else {};
        in
          result
          // {
            ${name} =
              override
              // checksOpt
              // {
                hostname = override.hostname or "${name}";
                profiles =
                  (override.profiles or {})
                  // {
                    system =
                      (override.profiles or {})
                  .system or {}
                      // {
                        path = deploy-rs.lib.${system}.activate.nixos host;
                      }
                      // lib.optionalAttrs (user != null) {
                        user = "root";
                        sshUser = user;
                      };
                  };
              };
          }
      ) {}
      names;
  in {inherit nodes;};
in {
  inherit mkDeploy;
}
