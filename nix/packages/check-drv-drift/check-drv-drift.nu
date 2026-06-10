# check-drv-drift
# Compare nixosConfigurations toplevel drvPaths between the working copy
# and a base revision. Hosts expected to drift (mid-migration) are allowed
# via: DRIFT_ALLOW=carbon,gallium nix run .#check-drv-drift
#
# Base defaults to the local `main` bookmark (the known-good point migration
# work branches from). Pass a different revset as the first argument, e.g.
#   nix run .#check-drv-drift -- @-
# Limit to a single host (one eval per side instead of full-fleet) with --host:
#   nix run .#check-drv-drift -- --host carbon

# Several things bake flake-SOURCE-derived state into a host, so ANY repo change
# rewrites them and drifts the host's drvPath even when its real config is
# unchanged. We neutralize the known ones via extendModules on each side of the
# compare — real deployed systems keep them; the drift check sees only true
# config differences:
#   - environment.etc."nixos".source = flake  (basic-settings, full source tree)
#   - environment.etc."nixos-revision".text = flake.rev/dirtyRev (basic-settings)
#   - programs.optnix  (nix/modules/nixos/optnix.nix bakes every option's
#     declaration PATH — which contains ${self} — into a generated options.json)
# The optnix strip is guarded by an option-existence check so hosts without the
# module (the servers) don't error.
const STRIP = ' (let r = builtins.tryEval ((c.extendModules { modules = [ ({ lib, options, ... }: { config = lib.mkMerge [ { environment.etc."nixos".enable = lib.mkForce false; environment.etc."nixos-revision".enable = lib.mkForce false; } (lib.mkIf (options.programs ? optnix) { programs.optnix.enable = lib.mkForce false; }) ]; }) ]; }).config.system.build.toplevel.drvPath); in if r.success then r.value else "(eval failed)")'

# Evaluate toplevel drvPaths for a flakeref. With --host, evaluate just that
# one host (cheap); otherwise map over every nixosConfiguration in one eval.
def drv-paths [flakeref: string, host?: string] {
  if ($host | is-empty) {
    nix eval --json $"($flakeref)#nixosConfigurations" --apply $"cs: builtins.mapAttrs \(_: c:($STRIP)) cs" |
      from json
  } else {
    let p = (nix eval --raw $"($flakeref)#nixosConfigurations.($host)" --apply $"c:($STRIP)")
    {($host): $p}
  }
}

def main [base: string = "main", --host: string] {
  let base_rev = jj log -r $base --no-graph -T commit_id | str trim
  let old = drv-paths $"git+file:.?rev=($base_rev)" $host
  let new = drv-paths "." $host

  let allow = (
    $env.DRIFT_ALLOW?
    | default ""
    | split row ","
    | each {|s| $s | str trim }
    | where {|s| $s != "" }
  )

  let hosts = (($old | columns) ++ ($new | columns)) | uniq | sort
  let report = $hosts | each {|h|
    let o = if $h in ($old | columns) { $old | get $h } else { "(absent)" }
    let n = if $h in ($new | columns) { $new | get $h } else { "(absent)" }
    {host: $h, drift: ($o != $n), allowed: ($h in $allow), old: $o, new: $n}
  }

  print ($report | select host drift allowed | table)

  let bad = $report | where {|r| $r.drift and (not $r.allowed) }
  if ($bad | is-not-empty) {
    print ""
    print "Unexpected drift — review before pushing:"
    for r in $bad { print $"  nix-diff ($r.old) ($r.new)" }
    exit 1
  }
}
