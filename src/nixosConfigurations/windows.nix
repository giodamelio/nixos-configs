{
  root,
  inputs,
  homelab,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  extraModules = [
    # Must be in extra modules because of the way load the config in the flake.nix
    # See: https://github.com/zhaofengli/colmena/issues/60#issuecomment-1047199551
    inputs.colmena.nixosModules.deploymentOptions
  ];

  modules = [root.nixosModules.systems-windows];
}
