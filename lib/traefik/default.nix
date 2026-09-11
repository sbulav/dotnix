# Pure renderer for `custom.containers.traefik.routes`.
#
# Kept in `lib/` (and free of `config`) so the rendered routers/services can be
# asserted by `checks/traefik-routes` without evaluating a whole NixOS system.
{ lib, ... }:
let
  inherit (lib)
    attrValues
    concatMapStringsSep
    filterAttrs
    listToAttrs
    mapAttrs
    nameValuePair
    optionalString
    ;

  # Mirrors the defaults of the `routes` submodule, so the renderer can also be
  # driven with partial route attrsets (the check does exactly that).
  withDefaults =
    name: route:
    {
      enable = true;
      service = name;
      middlewares = [ "auth-chain" ];
      clientIPs = [ ];
      pathRegexp = null;
      entrypoints = [ "websecure" ];
      certResolver = "production";
      passHostHeader = true;
    }
    // route;

  # Byte-identical to what the removed shared-traefik-*.nix helpers emitted:
  # changing the spacing or the parentheses rewrites every rule string in the
  # deployed dynamic configuration.
  mkRule =
    route:
    "Host(`${route.host}`)"
    +
      optionalString (route.clientIPs != [ ])
        " && (${concatMapStringsSep " || " (cidr: "ClientIP(`${cidr}`)") route.clientIPs})"
    + optionalString (route.pathRegexp != null) " && PathRegexp(`${route.pathRegexp}`)";

  enabledRoutes = routes: filterAttrs (_: route: route.enable) (mapAttrs withDefaults routes);

  # routes :: attrsOf route, keyed by router name
  # -> { routers = ...; services = ...; } for dynamicConfigOptions.http
  renderRoutes =
    routes:
    let
      enabled = enabledRoutes routes;
    in
    {
      routers = mapAttrs (_: route: {
        inherit (route) entrypoints service middlewares;
        rule = mkRule route;
        tls = {
          inherit (route) certResolver;
        };
      }) enabled;

      # Several routers legitimately share one backend (`<app>`,
      # `allowedips-<app>`, `bypass-<app>`), so the service is emitted once.
      # Genuinely conflicting definitions are caught by assertions in the
      # Traefik module.
      services = listToAttrs (
        map (
          route:
          nameValuePair route.service {
            loadBalancer = {
              inherit (route) passHostHeader;
              servers = [ { inherit (route) url; } ];
            };
          }
        ) (attrValues enabled)
      );
    };
in
{
  traefik = {
    inherit mkRule renderRoutes enabledRoutes;
  };
}
