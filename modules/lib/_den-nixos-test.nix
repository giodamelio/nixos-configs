# Boot real den-built hosts as a multi-VM NixOS test.
{
  inputs,
  lib,
}: {
  pkgs,
  name,
  fleet,
  nodes, # { vmNodeName = "denHostName"; }
  testScript,
  node ? (_: {}),
}: let
  system = pkgs.stdenv.hostPlatform.system;

  surface = {
    config,
    lib,
    ...
  }: {
    flake.denMainModules =
      lib.concatMapAttrs
      (_sys: hosts: lib.mapAttrs (_: h: h.mainModule) hosts)
      config.den.hosts;
  };

  fp = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
    systems = [system];
    imports = [inputs.den.flakeModule surface] ++ lib.toList fleet;
  };
in
  # mainModule bakes host/fleet/perSystem context via _module.args, so it
  # re-evaluates cleanly inside runNixOSTest's own nixosSystem.
  pkgs.testers.runNixOSTest {
    inherit name testScript;
    nodes =
      lib.mapAttrs (vmName: denHost: {
        imports = [fp.denMainModules.${denHost} (node vmName)];
      })
      nodes;
  }
