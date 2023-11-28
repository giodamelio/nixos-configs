{
  root,
  inputs,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  modules = [
    # Disk layout
    inputs.disko.nixosModules.disko
    root.disko.simple-hybrid

    # Boot with grub
    root.nixosModules.core-bootloader-grub

    # Basic packages I want on every system
    root.nixosModules.basic-packages

    # System specific config
    root.nixosModules.systems-bootstrap

    # Enable image generation
    inputs.nixos-generators.nixosModules.all-formats
  ];
}
