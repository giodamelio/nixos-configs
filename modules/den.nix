# den base wiring. den is an aspect-oriented config framework built on
# flake-parts; we run it beside Blueprint (see the flake.nix carve and
# tmp/den-migration-plan.md). import-tree (wired in flake.nix) loads every
# other module file under ./modules automatically.
#
# https://den.denful.dev — den.hosts declare machines, den.aspects declare
# cross-class features, and den emits standard nixosConfigurations/etc.
{
  inputs,
  lib,
  ...
}: {
  imports = [inputs.den.flakeModule];

  # flake-parts needs the systems its per-system outputs target. We emit no
  # perSystem outputs yet, so this only needs our hosts' platforms.
  systems = ["x86_64-linux" "aarch64-linux"];

  # Most users get a Home Manager environment; matches the Blueprint convention.
  den.schema.user.classes = lib.mkDefault ["homeManager"];
}
