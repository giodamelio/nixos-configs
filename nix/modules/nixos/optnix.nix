{
  pkgs,
  options,
  inputs,
  ...
}: let
  optnixLib = inputs.optnix.mkLib pkgs;
in {
  imports = [
    inputs.optnix.nixosModules.optnix
  ];

  programs.optnix = {
    enable = true;

    settings = {
      default_scope = "nixos";

      scopes.nixos = {
        description = "My personal NixOS configs";
        options-list-file = optnixLib.mkOptionsList {inherit options;};
        evaluator = "nix eval ~/nixos-configs#nixosConfigurations.cadmium.config.{{ .Option }}";
      };
    };
  };
}
