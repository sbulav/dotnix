{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.msmtp;
in {
  options.${namespace}.containers.msmtp = with types; {
    enable = mkBoolOpt false "Enable the msmtp email service ;";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";
  };
  config = mkIf cfg.enable {
    sops.secrets = {
      "email-password" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 1000;
      };
    };
    programs.msmtp = {
      enable = true;
      accounts = {
        gmail = {
          auth = true;
          host = "smtp.gmail.com";
          port = 587;
          tls = true;
          tls_starttls = true;
          from = "ZANOZA-notifications";
          user = "zppfan@gmail.com";
          passwordeval = "${pkgs.coreutils}/bin/cat ${config.sops.secrets.email-password.path}";
        };
      };
      extraConfig = ''
        account default: gmail
      '';
    };

  environment.etc = {
    "aliases" = {
      text = ''
        root: zppfan@gmail.com
      '';
      mode = "0644";
      };
  };
  };

}
