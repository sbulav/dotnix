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
  inherit (lib) optionalString optionalAttrs;
in
let
  cfg = config.system.security.gpg;

  gpgConf = ''
    use-agent
    pinentry-mode loopback
  '';

  gpgAgentConf = let
    smartcardConfig = optionalString cfg.smartcard.enable ''
      # Smartcard configuration
      scdaemon-program ${pkgs.gnupg}/libexec/scdaemon
      ${optionalString cfg.smartcard.disableCCID "disable-ccid"}
      ${optionalString cfg.smartcard.usePCSC "disable-scdaemon"}
      ${optionalString (cfg.smartcard.readerPort != 0) "reader-port ${toString cfg.smartcard.readerPort}"}
      ${optionalString cfg.smartcard.allowMulti "allow-multi"}
      enable-putty-support
    '';
  in ''
    enable-ssh-support
    default-cache-ttl 28800
    max-cache-ttl 28800
    allow-loopback-pinentry
    ${smartcardConfig}
  '';
in
{
  options.system.security.gpg = with types; {
    enable = mkBoolOpt false "Whether or not to enable GPG.";
    agentTimeout = mkOpt int 5 "The amount of time to wait before continuing with shell init.";
    
    smartcard = {
      enable = mkBoolOpt false "Enable smartcard support for GPG";
      usePCSC = mkBoolOpt true "Use PCSC daemon for smartcard access (recommended)";
      readerPort = mkOpt types.int 0 "Reader port for scdaemon (0 for auto)";
      disableCCID = mkBoolOpt false "Disable CCID support in scdaemon";
      allowMulti = mkBoolOpt true "Allow multiple connections to the same card";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # NOTE: This should already have been added by programs.gpg, but
      # keeping it here for now just in case.
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

      home.file = {
        ".gnupg/.keep".text = "";

        ".gnupg/gpg.conf".text = gpgConf;
        ".gnupg/gpg-agent.conf".text = gpgAgentConf;
      };
    }

    (mkIf cfg.smartcard.enable {
      # Add smartcard tools when smartcard is enabled
      environment.systemPackages = with pkgs; [
        gnupg-pkcs11-scd
      ];

      # Add PCSC dependency to gpg-agent service
      systemd.services.gpg-agent = {
        after = [ "pcscd.service" ];
        wants = [ "pcscd.service" ];
      };
    })
  ]);
}
