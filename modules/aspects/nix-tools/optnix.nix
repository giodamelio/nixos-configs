# optnix — interactive NixOS option search. Converted from
# nix/modules/nixos/optnix.nix. Keeps the external optnix input (module import +
# mkLib) via the file-scope `inputs` closure; `options` is the standard NixOS
# module arg. The harness strips programs.optnix (it bakes ${self} paths).
{inputs, ...}: {
  den.aspects.optnix.nixos = {
    pkgs,
    options,
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
  };
}
