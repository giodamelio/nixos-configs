# affinity — Affinity suite (Photo/Designer/Publisher) via Wine.
{inputs, ...}: {
  den.aspects.affinity.nixos = {pkgs, ...}: {
    environment.systemPackages = [
      # Apply upstream's overlay as a plain function so the package evaluates
      # against our pkgs (our allowUnfree predicate) instead of the flake's
      # warning-wrapped `packages` output.
      (inputs.affinity-nix.overlays.default pkgs pkgs).affinity-v3
    ];
  };
}
