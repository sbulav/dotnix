# Route to bypass authelia based on clientIP
{
  app ? "test",
  host ? "test.sbulav.ru",
  url ? "http://localhost:80",
  middleware ? [ "auth-chain" ],
  route_enabled ? false,
  clientips ? "ClientIP(`12.34.56.78/32`) || ClientIP(`192.168.89.0/24`)",
  ...
}:
{
  containers.traefik.config.services.traefik.dynamicConfigOptions.http =
    if route_enabled then
      {
        routers."allowedips-${app}" = {
          entrypoints = [ "websecure" ];
          rule = "Host(`${host}`) && (${clientips})";
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
      }
    else
      { };
}
