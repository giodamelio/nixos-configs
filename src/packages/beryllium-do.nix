{
  root,
  inputs,
  system,
  debug,
  ...
}:
inputs.nixos-generators.nixosGenerate {
  inherit system;
  format = "do";
  modules = [
    root.nixosModules.systems-beryllium
  ];
}
