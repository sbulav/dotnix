# `<app>-requeue`: drop oversized items from a running *arr queue so the
# app re-grabs a smaller release.
#
# Setting Maximum Size (shared-arr-api-settings.nix) only gates *future*
# grabs — downloads already in flight were accepted under the old, unset
# cap and have to be kicked out by hand. That is what this does.
#
# Lives on the host, not in the container: the containers are ephemeral
# and carry no shell tooling. It talks to the container over its private
# address and reads the API key out of the bind-mounted config.xml, so it
# needs root.
{
  pkgs,
  lib,
  app,
  url,
  configXml,
  apiVersion ? "v3",
  # extra GET params, e.g. so the listing also covers items whose
  # movie/series lookup failed
  queueParams ? "",
  defaultMaxGB,
}:
pkgs.writeShellApplication {
  name = "${app}-requeue";
  runtimeInputs = [
    pkgs.curl
    pkgs.jq
    pkgs.gawk
  ];
  text = ''
    APP=${lib.escapeShellArg app}
    API=${lib.escapeShellArg "${url}/api/${apiVersion}"}
    CONFIG_XML=${lib.escapeShellArg configXml}
    QUEUE_PARAMS=${lib.escapeShellArg queueParams}
    DEFAULT_MAX_GB=${toString defaultMaxGB}
    ${builtins.readFile ./arr-requeue.sh}
  '';
  meta.description = "Requeue oversized ${app} downloads at a smaller size";
}
