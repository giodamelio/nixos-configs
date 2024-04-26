{
  root,
  inputs,
  ...
}:
inputs.nix-darwin.lib.darwinSystem {
  modules = [root.nixosModules.machines.giodamelio-back9.default];
  specialArgs = {};
}
