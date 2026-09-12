# Pure renderer and validator for `custom.containers.traefik.routes`.
#
# Kept in `lib/` (and free of `config`) so both the rendered routers/services
# and the assertions guarding them can be exercised by `checks/traefik-routes`
# without evaluating a whole NixOS system.
{ lib, ... }:
let
  inherit (lib)
    attrNames
    attrValues
    concatLists
    concatMap
    concatMapStringsSep
    concatStringsSep
    elem
    filter
    filterAttrs
    groupBy
    hasInfix
    hasPrefix
    length
    listToAttrs
    mapAttrs
    mapAttrsToList
    nameValuePair
    optionalString
    removePrefix
    sort
    subtractLists
    unique
    ;

  # Single source of truth for the route defaults: the `routes` submodule in
  # modules/nixos/containers/traefik feeds these straight into its `mkOpt`
  # calls, and `withDefaults` applies the same values to the partial attrsets
  # the lib is driven with directly (the check does exactly that). Editing a
  # default here changes production and the check together.
  routeDefaults = {
    enable = true;
    middlewares = [ "auth-chain" ];
    clientIPs = [ ];
    pathRegexp = null;
    entrypoints = [ "websecure" ];
    certResolver = "production";
    passHostHeader = true;
  };

  # `service` is the one default that cannot live in `routeDefaults`: it is the
  # route's own name, which is only known per route — the submodule takes it
  # from its `name` argument, `withDefaults` from the attribute key. `host` and
  # `url` have no default at all; they are required.
  routeFields = sort (a: b: a < b) (
    attrNames routeDefaults
    ++ [
      "service"
      "host"
      "url"
    ]
  );

  # null when every attribute of `route` is a known route field, otherwise the
  # message `withDefaults` throws. Exposed so the check can assert the text
  # names both the route and the offending attributes — `builtins.tryEval`
  # only reports *that* an evaluation failed, never why.
  routeAttrsError =
    name: route:
    let
      unknown = subtractLists routeFields (attrNames route);
    in
    if unknown == [ ] then
      null
    else
      ''
        custom.containers.traefik.routes."${name}": unknown route attribute(s): ${concatStringsSep ", " unknown}.
        Known route attributes: ${concatStringsSep ", " routeFields}.'';

  # Applies the defaults, and refuses a route carrying anything else: `//`
  # would silently swallow a misspelt `middlewear = [ ... ]`, which is the
  # whole bug class the typed option exists to kill.
  withDefaults =
    name: route:
    let
      error = routeAttrsError name route;
    in
    if error != null then throw error else routeDefaults // { service = name; } // route;

  # Loose but real: dotted quad with an optional prefix, or an IPv6 form (at
  # least one colon) with an optional prefix. Catches `banana` and `10.0.0.0/x`
  # without pretending to be a full address parser.
  cidrPattern = "(([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?)|([0-9a-fA-F]{0,4}(:[0-9a-fA-F]{0,4}){1,7}(/[0-9]{1,3})?)";

  isCidr = value: builtins.match cidrPattern value != null;

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
      # Genuinely conflicting definitions are caught by `routeAssertions`.
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

  routeLabel = route: ''custom.containers.traefik.routes."${route.name}"'';

  # The `[ { assertion; message; } ]` list the Traefik module hands to NixOS.
  # Pure, so the check can drive it with hand-written broken routes.
  routeAssertions =
    {
      routes,
      knownMiddlewares,
    }:
    let
      # Per-route checks run over *every* route, disabled ones included: a
      # route parked with `enable = false` must not be allowed to rot until
      # someone flips it back on.
      allRoutes = mapAttrsToList (name: route: route // { inherit name; }) (mapAttrs withDefaults routes);
      enabled = filter (route: route.enable) allRoutes;

      middlewareAssertions = concatMap (
        route:
        map (middleware: {
          assertion = elem middleware knownMiddlewares;
          message = ''
            ${routeLabel route}: unknown middleware "${middleware}".
            Known middlewares: ${concatStringsSep ", " knownMiddlewares}.
            Fix the name, or append the middleware to custom.containers.traefik.knownMiddlewares
            in the module that defines it.'';
        }) route.middlewares
      ) allRoutes;

      urlAssertions = map (route: {
        assertion = builtins.match "https?://.+" route.url != null;
        message = ''${routeLabel route}: url "${route.url}" must be an absolute http:// or https:// backend URL.'';
      }) allRoutes;

      hostAssertions = map (route: {
        assertion = route.host != "";
        message = "${routeLabel route}: host must be a non-empty FQDN for the Host() matcher.";
      }) allRoutes;

      # `host`, `clientIPs` and `pathRegexp` are interpolated raw inside
      # backtick-quoted Traefik matchers, so a backtick in any of them yields a
      # rule Nix happily builds and Traefik refuses to parse at runtime.
      backtickAssertions = concatMap (
        route:
        map
          (field: {
            assertion = !hasInfix "`" field.value;
            message = "${routeLabel route}: ${field.name} must not contain a backtick — it is interpolated inside a backtick-quoted Traefik matcher.";
          })
          (
            [
              {
                name = "host";
                value = route.host;
              }
            ]
            ++ map (cidr: {
              name = ''clientIPs entry "${cidr}"'';
              value = cidr;
            }) route.clientIPs
            ++ lib.optional (route.pathRegexp != null) {
              name = "pathRegexp";
              value = route.pathRegexp;
            }
          )
      ) allRoutes;

      cidrAssertions = concatMap (
        route:
        map (cidr: {
          assertion = isCidr cidr;
          message = ''${routeLabel route}: clientIPs entry "${cidr}" is not an IPv4/IPv6 address or CIDR range.'';
        }) route.clientIPs
      ) allRoutes;

      # `service` defaults to the router name, so an `allowedips-<app>` /
      # `bypass-<app>` router that forgets it emits a *second* Traefik service
      # pointing at the same backend instead of sharing `<app>`.
      sharedRouterAssertions = map (
        route:
        let
          shared = removePrefix "bypass-" (removePrefix "allowedips-" route.name);
        in
        {
          assertion =
            !(hasPrefix "allowedips-" route.name || hasPrefix "bypass-" route.name)
            || route.service != route.name;
          message = ''${routeLabel route}: add `service = "${shared}";` — this router shares a backend with "${shared}", and without it Traefik gets a second service named "${route.name}".'';
        }
      ) allRoutes;

      # `<app>`, `allowedips-<app>` and `bypass-<app>` deliberately share one
      # Traefik service; that service is emitted once, so the routers sharing
      # it must agree on what it points at. Grouped over enabled routes only —
      # a stale disabled route may legitimately still name an old backend.
      backendAssertions = concatLists (
        mapAttrsToList (
          service: routes':
          let
            routerNames = concatMapStringsSep ", " (route: ''"${route.name}"'') routes';
            urls = unique (map (route: route.url) routes');
            passHostHeaders = unique (map (route: route.passHostHeader) routes');
          in
          [
            {
              assertion = length urls <= 1;
              message = ''
                custom.containers.traefik.routes: routers ${routerNames} share the Traefik service
                "${service}" but disagree on url: ${concatStringsSep ", " urls}.'';
            }
            {
              assertion = length passHostHeaders <= 1;
              message = ''
                custom.containers.traefik.routes: routers ${routerNames} share the Traefik service
                "${service}" but disagree on passHostHeader.'';
            }
          ]
        ) (groupBy (route: route.service) enabled)
      );
    in
    middlewareAssertions
    ++ urlAssertions
    ++ hostAssertions
    ++ backtickAssertions
    ++ cidrAssertions
    ++ sharedRouterAssertions
    ++ backendAssertions;
in
{
  traefik = {
    inherit
      mkRule
      renderRoutes
      enabledRoutes
      routeDefaults
      routeFields
      routeAttrsError
      routeAssertions
      ;
  };
}
