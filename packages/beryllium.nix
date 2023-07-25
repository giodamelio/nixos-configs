{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: { };
in
inputs.nixos-generators.nixosGenerate {
  system = "x86_64-linux";
  format = "do";
  modules = [
    nixosModule
  ];
}
