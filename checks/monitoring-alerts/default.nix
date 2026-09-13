{
  lib,
  runCommand,
  prometheus,
  writeText,
  ...
}:
let
  grafanaRules = builtins.fromJSON (
    builtins.readFile ../../modules/nixos/containers/grafana/alerting/rules.json
  );
  queries = lib.concatMap (
    rule:
    map (query: {
      record = "migration_check_${lib.replaceStrings [ "-" ] [ "_" ] rule.uid}_${query.refId}";
      expr = query.model.expr;
    }) (builtins.filter (query: query.model ? expr && query.datasourceUid != "__expr__") rule.data)
  ) grafanaRules;
  rules = writeText "monitoring-alert-queries.json" (
    builtins.toJSON {
      groups = [
        {
          name = "monitoring-alert-query-syntax";
          rules = queries;
        }
      ];
    }
  );
in
runCommand "monitoring-alert-queries" { nativeBuildInputs = [ prometheus.cli ]; } ''
  promtool check rules ${rules}
  touch "$out"
''
