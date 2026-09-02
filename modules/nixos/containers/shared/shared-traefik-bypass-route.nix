# Route to bypass authelia based on regexp
{
  app ? "test",
  host ? "test.sbulav.ru",
  url ? "http://localhost:80",
  middleware ? [ "auth-chain" ],
  route_enabled ? false,
  pathregexp ? "(?i)^/products",
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
      routers."bypass-${app}" = {
        entrypoints = [ "websecure" ];
        # https://doc.traefik.io/traefik/routing/routers/#path-pathprefix-and-pathregexp
        rule = "Host(`${host}`) && PathRegexp(`${pathregexp}`)";
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
