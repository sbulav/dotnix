{
  lib,
  runCommand,
  jq,
  ...
}:
let
  # Three representative routes, in the shapes the container modules declare:
  # an authelia-protected default route, a LAN-only ClientIP route, and a
  # PathRegexp route that bypasses authelia for an application's own token
  # auth. All three share one backend — deliberately, as `<app>`,
  # `allowedips-<app>` and `bypass-<app>` do in the real configuration — and
  # that backend is on another machine, which the routes make explicit.
  backend = "http://beez.example.com:9200";
  host = "app.example.com";

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
    };

    # Emitted exactly once, despite three routers targeting it.
    services.app.loadBalancer = {
      passHostHeader = true;
      servers = [ { url = backend; } ];
    };
  };

  rendered = lib.custom.traefik.renderRoutes routes;
in
runCommand "traefik-routes-test"
  {
    nativeBuildInputs = [ jq ];
    expectedJson = builtins.toJSON expected;
    renderedJson = builtins.toJSON rendered;
    passAsFile = [
      "expectedJson"
      "renderedJson"
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

    # The three routers share one backend, so exactly one service is emitted.
    services=$(jq -r '.services | keys | join(",")' rendered.json)
    if [ "$services" != "app" ]; then
      echo "expected a single shared service \"app\", got: $services" >&2
      exit 1
    fi

    echo ok >"$out"
  ''
