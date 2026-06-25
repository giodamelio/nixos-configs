# check-drv-drift
# Compare nixosConfigurations toplevel drvPaths between the working copy
# and a base revision. Hosts expected to drift (mid-migration) are allowed
# via: DRIFT_ALLOW=carbon,gallium nix run .#check-drv-drift
#
# Base defaults to the local `main` bookmark (the known-good point migration
# work branches from). Pass a different revset as the first argument, e.g.
#   nix run .#check-drv-drift -- @-
# Limit to a single host with --host:
#   nix run .#check-drv-drift -- --host carbon
#
# The base side is materialized as a throwaway jj workspace checked out at the
# base rev and evaluated as a plain `path:` flakeref. We do NOT use
# `git+file:.?rev=` — nix's git fetcher shells out to `git fetch` which, in this
# environment, misparses `file:/…` as an ssh host and fails. Pass --base-path to
# reuse an existing workspace instead of creating a throwaway one.

# Several things bake flake-SOURCE-derived state into a host, so ANY repo change
# rewrites them and drifts the host's drvPath even when its real config is
# unchanged. We neutralize the known ones via extendModules on each side of the
# compare — real deployed systems keep them; the drift check sees only true
# config differences:
#   - environment.etc."nixos".source = flake  (basic-settings, full source tree)
#   - environment.etc."nixos-revision".text = flake.rev/dirtyRev (basic-settings)
#   - programs.optnix  (nix/modules/nixos/optnix.nix bakes every option's
#     declaration PATH — which contains ${self} — into a generated options.json)
# The optnix strip uses `optionalAttrs` (NOT `mkIf`): a `mkIf false` on
# `programs.optnix.enable` still introduces the `programs.optnix` path and trips
# the unknown-option check on hosts without the module (the servers).
# optionalAttrs collapses to `{}` so the path never appears.
const STRIP = ' (let r = builtins.tryEval ((c.extendModules { modules = [ ({ lib, options, ... }: { config = lib.mkMerge [ { environment.etc."nixos".enable = lib.mkForce false; environment.etc."nixos-revision".enable = lib.mkForce false; } (lib.optionalAttrs (options.programs ? optnix) { programs.optnix.enable = lib.mkForce false; }) ]; }) ]; }).config.system.build.toplevel.drvPath); in if r.success then r.value else "(eval failed)")'

# Names of all nixosConfigurations in a flakeref.
def host-names [flakeref: string] {
  nix eval --json $"($flakeref)#nixosConfigurations" --apply "cs: builtins.attrNames cs" | from json
}

# Evaluate ONE host's stripped toplevel drvPath. Per-host (not a single
# mapAttrs over the fleet) so that a host whose drvPath needs an IFD that fails
# to BUILD — e.g. a broken fixed-output derivation — yields "(eval failed)" for
# just that host instead of aborting the whole comparison. tryEval cannot catch
# IFD build failures, so we detect them via the process exit code here.
def drv-path-one [flakeref: string, host: string] {
  let res = (do { nix eval --raw $"($flakeref)#nixosConfigurations.($host)" --apply $"c:($STRIP)" } | complete)
  let out = ($res.stdout | str trim)
  if $res.exit_code == 0 and ($out | is-not-empty) { $out } else { "(eval failed)" }
}

def main [base: string = "main", --host: string, --base-path: string] {
  let base_rev = (jj log -r $base --no-graph -T commit_id | str trim)

  # Resolve the base flakeref, creating a throwaway workspace unless one was
  # supplied. ws_name is non-empty only for a workspace we must clean up.
  let ws = (
    if ($base_path | is-not-empty) {
      {ref: $"path:($base_path)", name: ""}
    } else {
      let name = $"drv-drift-($base_rev | str substring 0..12)"
      let path = $"/tmp/($name)"
      try { jj workspace forget $name } catch { }
      rm -rf $path
      jj workspace add --revision $base_rev $path | ignore
      {ref: $"path:($path)", name: $name, path: $path}
    }
  )

  let hosts = (
    if ($host | is-empty) {
      ((host-names $ws.ref) ++ (host-names ".")) | uniq | sort
    } else { [$host] }
  )

  let report = $hosts | each {|h|
    let o = (drv-path-one $ws.ref $h)
    let n = (drv-path-one "." $h)
    {host: $h, drift: ($o != $n), old: $o, new: $n}
  }

  # Tear down the throwaway workspace (no-op when --base-path was given).
  if ($ws.name | is-not-empty) {
    try { jj workspace forget $ws.name } catch { }
    rm -rf $ws.path
  }

  let allow = (
    $env.DRIFT_ALLOW?
    | default ""
    | split row ","
    | each {|s| $s | str trim }
    | where {|s| $s != "" }
  )

  let table = $report | each {|r| {host: $r.host, drift: $r.drift, allowed: ($r.host in $allow)} }
  print ($table | table)

  let bad = $report | where {|r| $r.drift and (not ($r.host in $allow)) }
  if ($bad | is-not-empty) {
    print ""
    print "Unexpected drift — review before pushing:"
    for r in $bad { print $"  nix-diff ($r.old) ($r.new)" }
    exit 1
  }
}
