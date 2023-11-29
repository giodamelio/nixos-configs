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
    root.disko.systems.cadmium

    # Boot with grub
    root.nixosModules.core-bootloader-grub

    # Basic packages I want on every system
    root.nixosModules.basic-packages

    (_: {
      networking.hostId = "3c510ad9";
    })
  ];
}
