# nixpkgs-stable — provides `pkgsStable`, an unfree-allowed stable nixpkgs
# instance, as a module arg. Converted from nix/modules/common/nixpkgs-stable.nix.
# Aspects that want stable packages `includes` this aspect and consume the
# `pkgsStable` module arg (e.g. software-development). `inputs` is closed over at
# file scope (the explicit escape hatch — per-system only injects `perSystem`).
{inputs, ...}: {
  den.aspects.nixpkgs-stable.nixos = {pkgs, ...}: {
    _module.args.pkgsStable = import inputs.nixpkgs-stable {
      inherit (pkgs) system;
      config.allowUnfree = true;
    };
  };
}
