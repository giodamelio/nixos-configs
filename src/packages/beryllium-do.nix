{ root, inputs, system, ... }:
inputs.nixos-generators.nixosGenerate {
  inherit system;
  format = "do";
  modules = [
    root.nixosModules.beryllium
  ];
}
