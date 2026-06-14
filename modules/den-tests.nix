{
  inputs,
  lib,
  ...
}: let
  # Every test fleet gets the real den modules (all aspects, schema, den.default)
  # minus: the real machines; the test wiring (would recurse, so denTest
  # declarations live under modules/checks/); and production fleet-data that
  # references real hosts not present in a test fleet (clients.nix grants to
  # cadmium/cesium, which would fail cross-host validation).
  base =
    inputs.import-tree.filterNot
    (
      p:
        lib.hasInfix "/hosts/" p
        || lib.hasInfix "/checks/" p
        || lib.hasSuffix "/den-tests.nix" p
        || lib.hasSuffix "/ssh/clients.nix" p
    )
    (inputs.self + "/modules");
in {
  options.perSystem = inputs.flake-parts.lib.mkPerSystemOption ({
    config,
    pkgs,
    system,
    lib,
    ...
  }: {
    options.denTests = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          system = lib.mkOption {
            type = lib.types.str;
            default = "x86_64-linux";
          };
          fleet = lib.mkOption {type = lib.types.unspecified;};
          nodes = lib.mkOption {type = lib.types.attrsOf lib.types.str;};
          testScript = lib.mkOption {type = lib.types.lines;};
          node = lib.mkOption {
            type = lib.types.unspecified;
            default = _: {};
          };
        };
      });
    };

    # Only materialize a test on the system its fleet targets.
    config.checks =
      lib.mapAttrs
      (name: t:
        (import ./lib/_den-nixos-test.nix {inherit inputs lib;}) {
          inherit pkgs name;
          fleet = [base t.fleet];
          inherit (t) nodes testScript node;
        })
      (lib.filterAttrs (_: t: t.system == system) config.denTests);
  });
}
