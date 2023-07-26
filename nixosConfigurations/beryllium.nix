{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      inputs.self.nixosModules.system-image-gen
      inputs.self.nixosModules.grub-boot
      inputs.self.nixosModules.beryllium
    ];
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
