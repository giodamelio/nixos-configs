{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      inputs.self.nixosModules.beryllium
    ];
  };
in
inputs.nixos-generators.nixosGenerate {
  system = "x86_64-linux";
  format = "do";
  modules = [
    nixosModule
  ];
}
