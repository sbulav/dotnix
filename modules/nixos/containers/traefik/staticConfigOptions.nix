{
  api = {
    dashboard = true;
    # Access the Traefik dashboard on <Traefik IP>:8080 of your server
    insecure = false;
  };
  log = {
    level = "INFO";
    filePath = "/traefik/logs/traefik.log";
    format = "json";
  };

  accessLog = {
    filePath = "/traefik/logs/access.log";
    format = "json";
    # Log access to Dashboard
    addInternals = true;
    # Buffer logs in memory before writing to disk
    bufferingSize = 100;
    filters.statusCodes = [
      "200-206"
      "400-499"
      "500-599"
    ];
  };
  entryPoints = {
    web = {
      address = ":80";
      asDefault = true;
      http.redirections.entrypoint = {
        to = "websecure";
        scheme = "https";
      };
      transport.respondingTimeouts = {
        readTimeout = "600s";
        idleTimeout = "600s";
        writeTimeout = "600s";
      };
    };

    websecure = {
      address = ":443";
      asDefault = true;
      # Default resolver for routers that don't set tls.certResolver themselves;
      # must name an entry in certificatesResolvers below.
      http.tls.certResolver = "production";
      transport.respondingTimeouts = {
        readTimeout = "600s";
        idleTimeout = "600s";
        writeTimeout = "600s";
      };
    };
  };

  certificatesResolvers = {
    # Resolving via cloudflare DNS, has rate limiting
    production.acme = {
      dnsChallenge = {
        provider = "cloudflare";
        resolvers = [
          "1.1.1.1:53"
          "1.0.0.1:53"
        ];
        delayBeforeCheck = 5;
      };
      # certificatesDuration deliberately left at its default (2160h = 90 days,
      # matching Let's Encrypt), which renews ~30 days before expiry. The unit
      # is HOURS — a small value like 180 delays renewal to the last day.
      storage = "/traefik/certs/acme.json"; # where acme certificates live
      caServer = "https://acme-v02.api.letsencrypt.org/directory";
    };
    # Issuing test certs, no rate limit
    staging.acme = {
      dnsChallenge = {
        provider = "cloudflare";
        resolvers = [
          "1.1.1.1:53"
          "1.0.0.1:53"
        ];
        delayBeforeCheck = 5;
      };
      storage = "/traefik/certs/acme.json"; # where acme certificates live
      caServer = "https://acme-staging-v02.api.letsencrypt.org/directory";
    };
  };
}
