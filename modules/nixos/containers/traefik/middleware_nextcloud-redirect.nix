{
  containers.traefik.config.services.traefik.dynamicConfigOptions.http.middlewares.nextcloud-redirect = {
    redirectRegex = {
      permanent = true;
      regex = "https://(.*)/.well-known/(card|cal)dav";
      replacement = "https://\${1}/remote.php/dav/";
    };
  };
}
