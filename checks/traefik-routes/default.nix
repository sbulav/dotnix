{
  lib,
  runCommand,
  jq,
  ...
}:
let
  inherit (lib.custom) traefik;

  # Representative routes, in the shapes the container modules declare: an
  # authelia-protected default route, a LAN-only ClientIP route, a PathRegexp
  # route that bypasses authelia for an application's own token auth, and an
  # `api` pair overriding entrypoints, certResolver and passHostHeader. Routers
  # in a group share one backend — deliberately, as `<app>`, `allowedips-<app>`
  # and `bypass-<app>` do in the real configuration — and that backend is on
  # another machine, which the routes make explicit.
  backend = "http://beez.example.com:9200";
  host = "app.example.com";

  apiBackend = "http://beez.example.com:9300";
  apiHost = "api.example.com";

  routes = {
    app = {
      inherit host;
      url = backend;
    };

    "allowedips-app" = {
      service = "app";
      inherit host;
      url = backend;
      middlewares = [
        "secure-headers"
        "allow-lan"
      ];
      clientIPs = [
        "172.16.64.0/24"
        "192.168.80.0/20"
      ];
    };

    "bypass-app" = {
      service = "app";
      inherit host;
      url = backend;
      middlewares = [ "secure-headers" ];
      pathRegexp = "^/api/|^/.well-known/app";
    };

    # Disabled routes must not reach the dynamic configuration at all.
    "allowedips-app-old" = {
      enable = false;
      service = "app";
      inherit host;
      url = "http://127.0.0.1:1";
      clientIPs = [ "10.0.0.0/8" ];
    };

    # Every non-default knob at once: extra entrypoint, staging resolver and a
    # backend that must see the original Host header rewritten away.
    api = {
      host = apiHost;
      url = apiBackend;
      middlewares = [ "secure-headers" ];
      entrypoints = [
        "web"
        "websecure"
      ];
      certResolver = "staging";
      passHostHeader = false;
    };

    # clientIPs *and* pathRegexp on one router, with an IPv6 range.
    "allowedips-api" = {
      service = "api";
      host = apiHost;
      url = apiBackend;
      middlewares = [
        "secure-headers"
        "allow-lan"
      ];
      clientIPs = [
        "172.16.64.0/24"
        "2001:db8::/32"
      ];
      pathRegexp = "^/metrics";
      entrypoints = [
        "web"
        "websecure"
      ];
      certResolver = "staging";
      passHostHeader = false;
    };
  };

  expected = {
    routers = {
      app = {
        entrypoints = [ "websecure" ];
        middlewares = [ "auth-chain" ];
        rule = "Host(`app.example.com`)";
        service = "app";
        tls.certResolver = "production";
      };
      "allowedips-app" = {
        entrypoints = [ "websecure" ];
        middlewares = [
          "secure-headers"
          "allow-lan"
        ];
        rule = "Host(`app.example.com`) && (ClientIP(`172.16.64.0/24`) || ClientIP(`192.168.80.0/20`))";
        service = "app";
        tls.certResolver = "production";
      };
      "bypass-app" = {
        entrypoints = [ "websecure" ];
        middlewares = [ "secure-headers" ];
        rule = "Host(`app.example.com`) && PathRegexp(`^/api/|^/.well-known/app`)";
        service = "app";
        tls.certResolver = "production";
      };
      api = {
        entrypoints = [
          "web"
          "websecure"
        ];
        middlewares = [ "secure-headers" ];
        rule = "Host(`api.example.com`)";
        service = "api";
        tls.certResolver = "staging";
      };
      # Host first, then the ClientIP alternatives, then PathRegexp.
      "allowedips-api" = {
        entrypoints = [
          "web"
          "websecure"
        ];
        middlewares = [
          "secure-headers"
          "allow-lan"
        ];
        rule = "Host(`api.example.com`) && (ClientIP(`172.16.64.0/24`) || ClientIP(`2001:db8::/32`)) && PathRegexp(`^/metrics`)";
        service = "api";
        tls.certResolver = "staging";
      };
    };

    # Emitted exactly once per backend, despite three routers targeting `app`
    # and two targeting `api`.
    services = {
      app.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = backend; } ];
      };
      api.loadBalancer = {
        passHostHeader = false;
        servers = [ { url = apiBackend; } ];
      };
    };
  };

  rendered = traefik.renderRoutes routes;

  # ---------------------------------------------------------------------------
  # Negative cases: every guard must actually fire, and name the route it is
  # complaining about. Driven straight through the pure validators, so a
  # regression shows up here instead of in a deployed Traefik.
  # ---------------------------------------------------------------------------

  knownMiddlewares = [
    "auth-chain"
    "secure-headers"
    "allow-lan"
  ];

  failures =
    badRoutes:
    map (a: a.message) (
      lib.filter (a: !a.assertion) (
        traefik.routeAssertions {
          routes = badRoutes;
          inherit knownMiddlewares;
        }
      )
    );

  # A failing assertion whose message mentions every one of `needles`.
  fires =
    name: needles: badRoutes:
    let
      msgs = failures badRoutes;
      hits = lib.filter (msg: lib.all (needle: lib.hasInfix needle msg) needles) msgs;
    in
    {
      inherit name;
      pass = hits != [ ];
      detail = "expected a failing assertion mentioning ${builtins.toJSON needles}; failing messages were ${builtins.toJSON msgs}";
    };

  holds =
    name: badRoutes:
    let
      msgs = failures badRoutes;
    in
    {
      inherit name;
      pass = msgs == [ ];
      detail = "expected no failing assertion, got ${builtins.toJSON msgs}";
    };

  valid = {
    inherit host;
    url = backend;
  };

  # `builtins.tryEval` reports only *that* evaluation failed, so the throw is
  # checked twice: tryEval proves it fires, `routeAttrsError` proves the text
  # names the route and the offending attribute.
  unknownKeyRoute = valid // {
    middlewear = [ "auth-chain" ];
  };
  unknownKeyError = traefik.routeAttrsError "app" unknownKeyRoute;
  unknownKeyThrows = builtins.tryEval (
    builtins.deepSeq (traefik.renderRoutes { app = unknownKeyRoute; }) true
  );

  cases = [
    {
      name = "unknown attribute key throws";
      pass = !unknownKeyThrows.success;
      detail = "renderRoutes accepted an unknown route attribute instead of throwing";
    }
    {
      name = "unknown attribute key names the route and the attribute";
      pass =
        unknownKeyError != null
        && lib.hasInfix ''routes."app"'' unknownKeyError
        && lib.hasInfix "middlewear" unknownKeyError;
      detail = "routeAttrsError returned ${builtins.toJSON unknownKeyError}";
    }
    {
      name = "a well-formed route reports no unknown attributes";
      pass = traefik.routeAttrsError "app" valid == null;
      detail = "routeAttrsError flagged a valid route: ${builtins.toJSON (traefik.routeAttrsError "app" valid)}";
    }

    (fires "unknown middleware" [ ''routes."app"'' "middlewear-chain" "Known middlewares:" ] {
      app = valid // {
        middlewares = [ "middlewear-chain" ];
      };
    })
    (fires "relative url" [ ''routes."app"'' "/backend" ] {
      app = valid // {
        url = "/backend";
      };
    })
    (fires "empty host" [ ''routes."app"'' "non-empty FQDN" ] {
      app = valid // {
        host = "";
      };
    })
    (fires "backtick in host" [ ''routes."app"'' "backtick" ] {
      app = valid // {
        host = "app.example.com`)||ClientIP(`0.0.0.0/0";
      };
    })
    (fires "backtick in pathRegexp" [ ''routes."app"'' "backtick" ] {
      app = valid // {
        pathRegexp = "^/x`";
      };
    })
    (fires "non-CIDR clientIPs entry" [ ''routes."app"'' "banana" "CIDR" ] {
      app = valid // {
        clientIPs = [ "banana" ];
      };
    })
    (fires "malformed prefix length" [ ''routes."app"'' "10.0.0.0/x" "CIDR" ] {
      app = valid // {
        clientIPs = [ "10.0.0.0/x" ];
      };
    })
    (fires "allowedips- router without service" [ ''routes."allowedips-app"'' ''service = "app";'' ] {
      "allowedips-app" = valid;
    })
    (fires "bypass- router without service" [ ''routes."bypass-app"'' ''service = "app";'' ] {
      "bypass-app" = valid;
    })
    (fires "shared service with disagreeing urls" [ ''"allowedips-app"'' "disagree on url" ] {
      app = valid;
      "allowedips-app" = valid // {
        service = "app";
        url = "http://127.0.0.1:9999";
      };
    })
    (fires "shared service with disagreeing passHostHeader"
      [ ''"allowedips-app"'' "disagree on passHostHeader" ]
      {
        app = valid;
        "allowedips-app" = valid // {
          service = "app";
          passHostHeader = false;
        };
      }
    )

    # A route parked with `enable = false` is still validated: its typos must
    # surface now, not when someone flips it back on.
    (fires "disabled route with an unknown middleware" [ ''routes."app"'' "middlewear-chain" ] {
      app = valid // {
        enable = false;
        middlewares = [ "middlewear-chain" ];
      };
    })
    # ... but a stale disabled route may legitimately still name an old
    # backend, so the shared-service comparison stays on enabled routes.
    (holds "disabled route may disagree with the live one about the backend" {
      app = valid;
      "allowedips-app-old" = valid // {
        enable = false;
        service = "app";
        url = "http://127.0.0.1:1";
      };
    })

    (holds "real-world CIDR forms are accepted" {
      app = valid // {
        clientIPs = [
          "172.16.64.0/24"
          "192.168.80.0/20"
          "127.0.0.1/32"
          "2001:db8::/32"
          "fd00::1"
        ];
      };
    })
    (holds "the rendered route set raises nothing" routes)
  ];

  failed = lib.filter (case: !case.pass) cases;
in
runCommand "traefik-routes-test"
  {
    nativeBuildInputs = [ jq ];
    expectedJson = builtins.toJSON expected;
    renderedJson = builtins.toJSON rendered;
    emptyJson = builtins.toJSON (traefik.renderRoutes { });
    caseCount = toString (builtins.length cases);
    failedJson = builtins.toJSON failed;
    passAsFile = [
      "expectedJson"
      "renderedJson"
      "emptyJson"
      "failedJson"
    ];
  }
  ''
    set -euo pipefail
    jq -S . <"$expectedJsonPath" >expected.json
    jq -S . <"$renderedJsonPath" >rendered.json

    if ! diff -u expected.json rendered.json; then
      echo "lib.custom.traefik.renderRoutes produced unexpected routers/services" >&2
      exit 1
    fi

    # Five routers, two shared backends, so exactly two services are emitted.
    services=$(jq -r '.services | keys | join(",")' rendered.json)
    if [ "$services" != "api,app" ]; then
      echo "expected the shared services \"api,app\", got: $services" >&2
      exit 1
    fi

    # No routes at all still renders the two (empty) attribute sets Traefik
    # expects, not `null` or a missing key.
    echo '{"routers":{},"services":{}}' | jq -S . >empty-expected.json
    jq -S . <"$emptyJsonPath" >empty.json
    if ! diff -u empty-expected.json empty.json; then
      echo "lib.custom.traefik.renderRoutes { } must render empty routers/services" >&2
      exit 1
    fi

    # Negative cases, driven through lib.custom.traefik.routeAssertions and the
    # unknown-attribute throw.
    jq -S . <"$failedJsonPath" >failed.json
    if [ "$(jq 'length' failed.json)" != "0" ]; then
      echo "route validation cases failed:" >&2
      jq -r '.[] | "  ✗ \(.name)\n      \(.detail)"' failed.json >&2
      exit 1
    fi
    echo "all $caseCount route validation cases passed"

    echo ok >"$out"
  ''
