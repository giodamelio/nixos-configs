{
  root,
  debug,
  inputs,
  ...
}: {system}: let
  minimalModules = [
    root.nixosModules.basic-packages
    root.nixosModules.systems-minimal-installer
  ];
in {
  installer-minimal-iso = inputs.nixos-generators.nixosGenerate {
    inherit system;
    format = "install-iso";
    modules = minimalModules;
  };
  installer-minimal-iso-hyperv = inputs.nixos-generators.nixosGenerate {
    inherit system;
    format = "install-iso-hyperv";
    modules = minimalModules;
  };
}
