{
  inputs,
  lib,
  ...
}: let
  # Every test fleet gets the real den modules (all aspects, schema, den.default)
  # minus: the real machines (the /hosts/ subtree); and the specific files below.
  # Whole subtrees are matched by infix (no rename risk); individual files are
  # matched as exact paths relative to the modules/ root (import-tree strips that
  # root before filtering) and asserted to exist — so renaming or moving one
  # fails LOUD right here instead of silently re-including it and surfacing later
  # as a baffling "unknown host cadmium" deep in a test eval.
  excludedFiles = [
    "den-tests.nix" # this test wiring itself — would recurse
    "aspects/ssh/clients.nix" # grants to real hosts (cadmium/cesium) -> cross-host throw
  ];
  staleExclusions = lib.filter (f: !(builtins.pathExists (inputs.self + "/modules/${f}"))) excludedFiles;

  base = assert lib.assertMsg (staleExclusions == []) ''
    den-tests.nix: test-fleet exclusion target(s) no longer exist (renamed or moved?):
      ${lib.concatStringsSep "\n  " staleExclusions}
    Update `excludedFiles` in modules/den-tests.nix to match.
  '';
    inputs.import-tree.filterNot
    (
      p:
        lib.hasInfix "/hosts/" p
        || lib.hasInfix "/checks/" p
        || lib.any (f: lib.hasSuffix "/${f}" p) excludedFiles
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
