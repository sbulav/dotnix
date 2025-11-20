# Typical route with authentication via authelia and cert via cloudflare
{
  app ? "test",
  host ? "test.sbulav.ru",
  url ? "http://localhost:80",
  middleware ? [ "auth-chain" ],
  route_enabled ? false,
  ...
}:
{
  config,
  lib,
  namespace,
  ...
}:
{
  config = lib.mkIf (route_enabled && config.${namespace}.containers.traefik.enable) {
    containers.traefik.config.services.traefik.dynamicConfigOptions.http = {
      routers.${app} = {
        entrypoints = [ "websecure" ];
        rule = "Host(`${host}`)";
        service = "${app}";
        middlewares = middleware;
        tls = {
          certResolver = "production";
        };
      };
      services.${app} = {
        loadBalancer = {
          passHostHeader = true;
          servers = [
            {
              url = "${url}";
            }
          ];
        };
      };
    };
  };
}
