{
  containers.traefik.config.services.traefik.dynamicConfigOptions.http.middlewares.secure-headers-jellyfin =
    {
      headers = {
        sslRedirect = true;
        accessControlMaxAge = "100";
        stsSeconds = "31536000"; # force browsers to only connect over https
        stsIncludeSubdomains = true; # force browsers to only connect over https
        stsPreload = true; # force browsers to only connect over https
        forceSTSHeader = true; # force browsers to only connect over https
        contentTypeNosniff = true; # sets x-content-type-options header value to "nosniff", reduces risk of drive-by downloads
        frameDeny = false; # sets x-frame-options header value to "deny", prevents attacker from spoofing website in order to fool users into clicking something that is not there
        browserXssFilter = true; # sets x-xss-protection header value to "1; mode=block", which prevents page from loading if detecting a cross-site scripting attack
        # NOTE: contentSecurityPolicy intentionally omitted. It must be a single
        # string (a list serializes to an invalid header browsers discard), and
        # Jellyfin's web UI needs inline scripts and blob: URLs, so a strict
        # policy would break playback/artwork. Add a tested CSP here if desired.
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
