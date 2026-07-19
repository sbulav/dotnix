{
  namespace,
  config,
  ...
}:
{
  containers.traefik.config.services.traefik.dynamicConfigOptions.http.middlewares.authelia = {
    forwardAuth = {
      address = "http://${
        config.${namespace}.containers.authelia.localAddress
      }:9091/api/authz/forward-auth";
      trustForwardHeader = true;
      # Only forward what authelia needs (session cookie + content negotiation).
      # Crucially this keeps the client's Authorization header away from
      # authelia: jellyfin clients send "Authorization: MediaBrowser ..." which
      # authelia fails to parse ("invalid scheme") and rejects the request even
      # with a valid session. Traefik still adds X-Forwarded-* itself.
      authRequestHeaders = [
        "Accept"
        "Cookie"
      ];
      authResponseHeaders = [
        "Remote-User"
        "Remote-Groups"
        "Remote-Name"
        "Remote-Email"
      ];
    };
  };
}
