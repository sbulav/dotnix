{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.security.gpg;

  pinentryBin =
    if pkgs.stdenv.isDarwin then
      "${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac"
    else
      "${pkgs.pinentry-curses}/bin/pinentry-curses";

  gpgConf = ''
    use-agent
  '';

  gpgAgentConf = ''
    enable-ssh-support
    default-cache-ttl 28800
    max-cache-ttl 28800
    pinentry-program ${pinentryBin}
  '';

  launchAgent = ''
    ${pkgs.coreutils}/bin/timeout ${builtins.toString cfg.agentTimeout} ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
  '';
in
{
  options.custom.security.gpg = with types; {
    enable = mkBoolOpt false "Whether to enable GPG configuration";
    agentTimeout = mkOpt int 5 "The amount of time to wait before continuing with shell init";
    yubikeyKeyId = mkOpt str "" "YubiKey GPG key ID (auto-detected if empty)";
    fallbackKeyId = mkOpt str "7C43420F61CEC7FB" "Fallback GPG key ID when YubiKey unavailable";
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.gnupg ];

    home.file = {
      ".gnupg/.keep".text = "";
      ".gnupg/gpg.conf".text = gpgConf;
      ".gnupg/gpg-agent.conf".text = gpgAgentConf;
    };

    # SSH_AUTH_SOCK is evaluated at shell startup via gpgconf; set in each
    # shell's init rather than sessionVariables to ensure the agent is running.
    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      ${launchAgent}
      export GPG_TTY="$(tty)"
      export SSH_AUTH_SOCK="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)"
    '';

    programs.zsh.initExtra = mkIf config.programs.zsh.enable ''
      ${launchAgent}
      export GPG_TTY="$(tty)"
      export SSH_AUTH_SOCK="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)"
    '';

    programs.fish.interactiveShellInit = mkIf config.programs.fish.enable ''
      ${launchAgent}
      set -gx GPG_TTY (tty)
      set -gx SSH_AUTH_SOCK (${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)
    '';
  };
}
