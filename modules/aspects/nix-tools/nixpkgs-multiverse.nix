{inputs, ...}: {
  den.aspects.nixpkgs-multiverse.nixos = {pkgs, ...}: {
    imports = [inputs.multiverse.nixosModules.default];

    multiverse = {
      enable = true;
      config.allowUnfree = true;
    };

    # perSystem.multiverse.mvs would bootstrap its own nixpkgs release; build it on ours instead.
    environment.systemPackages = [(pkgs.extend inputs.multiverse.overlays.default).mvs];
  };
}
