# per-system — injects a single Blueprint-style module arg, `perSystem`, into
# every aspect class body, so converted aspects can pull packages out of flake
# inputs with `perSystem.<input>.<pkg>` instead of spelling out
# `inputs.<input>.packages.${system}`.
#
# Deliberately NOT `flake`/`inputs`: an ambient `flake`/`inputs` arg would let
# any aspect reach `flake.nixosModules.*` / `inputs.self.nixosModules.*` and
# re-import Blueprint modules, bypassing den's aspect composition. `perSystem`
# only exposes per-system *packages*, so it can't be used to smuggle modules in.
#
#   - The repo's own packages (Blueprint's `packages` output) are reachable as
#     `perSystem.self.<pkg>` — `self` is just another input.
#   - The few aspects that genuinely need a non-package flake value
#     (`inputs.self.lib.*`, the flake source tree, a stable nixpkgs import,
#     an external input's module) take `{ inputs, ... }` at *file* scope — an
#     explicit, visible escape hatch, not an ambient arg.
#
# Mechanism: a base aspect that sets `_module.args.perSystem` for the `nixos`
# and `homeManager` classes, included in den.default (modules/den.nix). `pkgs`
# is always present in both class bodies, so the evaluating system is read from
# `pkgs.stdenv.hostPlatform.system`.
#
# Note: `perSystem` is a module arg, available in an aspect's config body, NOT
# at the `imports = [ ... ]` level (imports resolve before module args).
{inputs, ...}: let
  # perSystem.<input> reproduces Blueprint's per-system package view: the
  # input's legacyPackages overlaid by its packages, for the evaluating system.
  # Lazy over all inputs — only forced entries evaluate.
  mkPerSystem = system:
    builtins.mapAttrs
    (_name: input: (input.legacyPackages.${system} or {}) // (input.packages.${system} or {}))
    inputs;

  provide = {pkgs, ...}: {
    _module.args.perSystem = mkPerSystem pkgs.stdenv.hostPlatform.system;
  };
in {
  den.aspects.per-system = {
    nixos = provide;
    homeManager = provide;
  };
}
