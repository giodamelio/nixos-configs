{
  root,
  inputs,
  system,
  debug,
  ...
}:
inputs.nixos-generators.nixosGenerate {
  inherit system;
  format = "hyperv";
  modules = [
    root.nixosModules.systems-beryllium
  ];
}
