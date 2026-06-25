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

  # den's instantiate is handed the forward-resolved module list (full
  # cross-entity resolution — grants, mesh peers). Return that list instead of
  # building a system, so runNixOSTest builds each node from it and keeps the
  # cross-host data; a host's mainModule alone is single-host and drops it.
  exposeModules = {lib, ...}: {
    den.schema.host.imports = [{config.instantiate = lib.mkForce (args: args.modules);}];
  };

  fp = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
    systems = [system];
    imports = [inputs.den.flakeModule exposeModules] ++ lib.toList fleet;
  };

  # Lower-level than pkgs.testers.runNixOSTest: omit node.pkgs so nodes keep the
  # nixpkgs the den modules set (their nixpkgs.hostPlatform), instead of the
  # read-only pkgs runNixOSTest forces (which collides with it).
  nixosLib = import "${inputs.nixpkgs}/nixos/lib" {inherit lib;};
in
  nixosLib.runTest {
    inherit name testScript;
    hostPkgs = pkgs;
    nodes =
      lib.mapAttrs (vmName: denHost: {
        imports = fp.nixosConfigurations.${denHost} ++ [(node vmName)];
      })
      nodes;
  }
