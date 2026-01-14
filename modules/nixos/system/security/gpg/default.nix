{
  options,
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.security.gpg;
in
{
  options.system.security.gpg = with types; {
    enable = mkBoolOpt false "Whether or not to enable GPG.";
    agentTimeout = mkOpt int 5 "The amount of time to wait before continuing with shell init.";
  };

  config = mkIf cfg.enable {
    environment.shellInit = ''
      export GPG_TTY="$(tty)"
      export SSH_AUTH_SOCK=$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)

      ${pkgs.coreutils}/bin/timeout ${builtins.toString cfg.agentTimeout} ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      gpg_agent_timeout_status=$?

      if [ "$gpg_agent_timeout_status" = 124 ]; then
        # Command timed out...
        echo "GPG Agent timed out..."
        echo 'Run "gpgconf --launch gpg-agent" to try and launch it again.'
      fi
    '';

    environment.systemPackages = with pkgs; [
      gnupg
      pinentry-curses
    ];

    programs = {
      ssh.startAgent = false;

      gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        enableExtraSocket = true;
        pinentryPackage = pkgs.pinentry-gnome3;
      };
    };

    # Enable PC/SC Smart Card Daemon for smartcard support
    services.pcscd.enable = true;
  };
}
