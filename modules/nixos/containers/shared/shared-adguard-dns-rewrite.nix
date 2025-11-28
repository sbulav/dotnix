# DNS rewrite module, by default creating CNAME to adguard
{
  host ? "test.sbulav.ru",
  url ? "adguard.sbulav.ru",
  rewrite_enabled ? false,
  ...
}:
{
  config,
  lib,
  namespace,
  ...
}:
{
  config = lib.mkIf (rewrite_enabled && config.${namespace}.containers.adguard.enable) {
    containers.adguard.config.services.adguardhome.settings.filtering = {
      rewrites = [
        {
          domain = "${host}";
          answer = "${url}";
          enabled = true;
        }
      ];
    };
  };
}
