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
  den,
  ...
}: {
  imports = [inputs.den.flakeModule];

  # flake-parts needs the systems its per-system outputs target. We emit no
  # perSystem outputs yet, so this only needs our hosts' platforms.
  systems = ["x86_64-linux" "aarch64-linux"];

  # Most users get a Home Manager environment; matches the Blueprint convention.
  den.schema.user.classes = lib.mkDefault ["homeManager"];

  # Home-Manager integration: always use the system nixpkgs and install user
  # packages into the system per-user profile (Blueprint's convention). den's
  # home-manager battery applies den.schema.hm-host content only to hosts it
  # detects as HM hosts, so this never touches user-less hosts like rhodium
  # (whose nixos config has no `home-manager` option) — no guard needed.
  den.schema.hm-host.includes = [
    {
      nixos.home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
      };
    }
  ];

  # Base bundle every host pulls in (the old Blueprint shared modules, now
  # aspects). deployed-apps chains in reverse-proxy via `includes`;
  # basic-packages/basic-settings stand alone. These attach to every den host
  # via den.default — host-specific aspects attach to their host instead, never
  # here. (The old Blueprint `required` shim — a bare import of deployed-apps —
  # is unnecessary now that den.default includes deployed-apps directly.)
  den.default.includes = [
    den.aspects.per-system
    den.aspects.deployed-apps
    den.aspects.basic-packages
    den.aspects.basic-settings

    # Dual-class: CLIs on every system; overriding aliases only for HM users.
    den.aspects.modern-coreutils-replacements

    # Always-on Home-Manager base for every user (the old `home-required`
    # bundle, now a default). nix-activate is wanted by every user; shpool/zmx
    # gate themselves on host.role, so they are inert on desktops. These are
    # homeManager-only aspects, so they contribute nothing on hosts or on users
    # without the homeManager class.
    den.aspects.nix-activate
    den.aspects.shpool
    den.aspects.zmx
  ];
}
