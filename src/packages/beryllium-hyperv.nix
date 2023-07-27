{ root, inputs, system, ... }:
inputs.nixos-generators.nixosGenerate {
  inherit system;
  format = "hyperv";
  modules = [
    root.nixosModules.beryllium
  ];
}
