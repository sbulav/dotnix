{
  config,
  lib,
  namespace,
  ...
}:
{
  config = lib.mkIf config.${namespace}.containers.traefik.enable {
    containers.traefik.config.services.traefik.dynamicConfigOptions.http.middlewares.nextcloud-redirect =
      {
        redirectRegex = {
          permanent = true;
          regex = "https://(.*)/.well-known/(card|cal)dav";
          replacement = "https://\${1}/remote.php/dav/";
        };
      };
  };
}
