{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.apps.thunderbird;
in
{
  options.custom.apps.thunderbird = {
    enable = mkEnableOption "Thunderbird with the declarative work Exchange (IMAP) account";

    address = mkOpt types.str "s.bulavintsev@hh.ru" "Work mailbox address.";

    # On-prem Exchange wants the short login without the domain; the IT doc's
    # manual-setup warning about "Re-test" silently switching auth to Kerberos
    # does not apply here because the declarative account pins password auth.
    login = mkOpt types.str "s.bulavintsev" "IMAP/SMTP login (short, no domain).";

    host = mkOpt types.str "email.hh.ru" ''
      Mail server host. On-prem Exchange per the IT doc; if the mailbox turns
      out to live in Exchange Online, IMAP/SMTP move to outlook.office365.com /
      smtp.office365.com and only work over the corporate VPN.
    '';
  };

  config = mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      profiles.work.isDefault = true;
    };

    accounts.email.accounts.work = {
      primary = true;
      address = cfg.address;
      userName = cfg.login;
      realName = config.custom.user.fullName;
      imap = {
        host = cfg.host;
        port = 993;
        tls.enable = true; # implicit SSL/TLS
      };
      smtp = {
        host = cfg.host;
        port = 587;
        tls = {
          enable = true;
          useStartTls = true;
        };
      };
      # Server settings are declarative; the password is not — Thunderbird
      # prompts on first connect and keeps it in its own store.
      thunderbird.enable = true;
    };
  };
}
