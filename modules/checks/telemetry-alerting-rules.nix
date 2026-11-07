_: {
  perSystem = {pkgs, ...}: {
    checks.telemetry-alerting-rules = let
      rules = import ../aspects/telemetry-alerting/_rules.nix;
      rulesFile = (pkgs.formats.yaml {}).generate "rules.yml" rules.metrics;
    in
      pkgs.runCommand "telemetry-alerting-rules" {nativeBuildInputs = [pkgs.victoriametrics];} ''
        cp ${rulesFile} rules.yml
        cp ${../aspects/telemetry-alerting/tests/rules.test.yml} rules.test.yml
        vmalert-tool unittest --files rules.test.yml
        touch $out
      '';
  };
}
