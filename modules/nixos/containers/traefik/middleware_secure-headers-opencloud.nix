{
  containers.traefik.config.services.traefik.dynamicConfigOptions.http.middlewares.secure-headers-opencloud =
    {
      headers = {
        sslRedirect = true;
        accessControlMaxAge = "100";
        stsSeconds = "31536000";
        stsIncludeSubdomains = true;
        stsPreload = true;
        forceSTSHeader = true;
        contentTypeNosniff = true;
        # OpenCloud iframes itself for the OIDC silent-renew flow, so X-Frame-Options must not be DENY.
        frameDeny = false;
        browserXssFilter = true;
        # NOTE: contentSecurityPolicy intentionally omitted. OpenCloud serves its own
        # CSP from /etc/opencloud/csp.yaml (configured via services.opencloud.settings.csp).
        # Setting one here would override OpenCloud's, breaking the cross-origin token
        # exchange with Authelia and blob workers used by the web UI.
        referrerPolicy = "same-origin";
        addVaryHeader = true;
        customResponseHeaders = {
          X-Robots-Tag = "none,noarchive,nosnippet,notranslate,noimageindex";
          server = "";
          X-Forwarded-Proto = "https";
        };
        sslProxyHeaders = {
          X-Forwarded-Proto = "https";
        };
      };
    };
}
