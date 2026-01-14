{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.custom.security.gpg;

  gpgConf = ''
    use-agent
  '';

  gpgAgentConf = ''
    enable-ssh-support
    default-cache-ttl 28800
    max-cache-ttl 28800
  '';
in {
  options.custom.security.gpg = with types; {
    enable = mkBoolOpt false "Whether to enable GPG configuration";
    agentTimeout = mkOpt int 5 "The amount of time to wait before continuing with shell init";
    yubikeyKeyId = mkOpt str "" "YubiKey GPG key ID (auto-detected if empty)";
    fallbackKeyId = mkOpt str "7C43420F61CEC7FB" "Fallback GPG key ID when YubiKey unavailable";
  };

  config = mkIf cfg.enable {
    home.file = {
      ".gnupg/.keep".text = "";
      ".gnupg/gpg.conf".text = gpgConf;
      ".gnupg/gpg-agent.conf".text = gpgAgentConf;
    };

    home.sessionVariables = {
      GPG_TTY = "$(tty)";
      SSH_AUTH_SOCK = "$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)";
    };

    # Ensure GPG agent is launched on shell init
    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      ${pkgs.coreutils}/bin/timeout ${builtins.toString cfg.agentTimeout} ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      gpg_agent_timeout_status=$?

      if [ "$gpg_agent_timeout_status" = 124 ]; then
        echo "GPG Agent timed out..."
        echo 'Run "gpgconf --launch gpg-agent" to try and launch it again.'
      fi
    '';

    programs.zsh.initExtra = mkIf config.programs.zsh.enable ''
      ${pkgs.coreutils}/bin/timeout ${builtins.toString cfg.agentTimeout} ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      gpg_agent_timeout_status=$?

      if [ "$gpg_agent_timeout_status" = 124 ]; then
        echo "GPG Agent timed out..."
        echo 'Run "gpgconf --launch gpg-agent" to try and launch it again.'
      fi
    '';

    programs.fish.interactiveShellInit = mkIf config.programs.fish.enable ''
      ${pkgs.coreutils}/bin/timeout ${builtins.toString cfg.agentTimeout} ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      set gpg_agent_timeout_status $status

      if test $gpg_agent_timeout_status -eq 124
        echo "GPG Agent timed out..."
        echo 'Run "gpgconf --launch gpg-agent" to try and launch it again.'
      end
    '';
  };
}
