# photo-editing — Affinity suite via Wine. Converted from
# nix/modules/nixos/photo-editing.nix.
_: {
  den.aspects.photo-editing.nixos = {perSystem, ...}: {
    environment.systemPackages = [
      perSystem.affinity-nix.affinity-v3
    ];
  };
}
