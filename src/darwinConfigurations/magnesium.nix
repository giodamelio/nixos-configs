{
  root,
  inputs,
  ...
}:
inputs.nix-darwin.lib.darwinSystem {
  modules = [root.nixosModules.machines.magnesium.default];
  specialArgs = {};
}
