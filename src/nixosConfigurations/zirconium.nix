{
  root,
  inputs,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  extraModules = [
    # Not sure why this has to be an extraModule instead of a regular module
    inputs.colmena.nixosModules.deploymentOptions
  ];

  modules = [root.nixosModules.machines.zirconium.default];
}
