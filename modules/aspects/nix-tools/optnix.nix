# optnix — interactive NixOS option search. Folded dual-class aspect:
#   - nixos half (was nix/modules/nixos/optnix.nix): the nixos scope.
#   - homeManager half (was nix/modules/home/optnix.nix): the home-manager scope.
# Keeps the external optnix input (module import + mkLib) via the file-scope
# `inputs` closure; `options` is the standard NixOS module arg. The harness
# strips programs.optnix (it bakes ${self} paths).
#
# Attachment: hosts that only want the nixos scope include this on the host
# (HM halves are not forwarded from hosts — cesium). cadmium attaches it to the
# user, which applies the homeManager half and forwards the nixos half to the
# host.
{inputs, ...}: {
  den.aspects.optnix.homeManager = {pkgs, ...}: let
    optnixLib = inputs.optnix.mkLib pkgs;
  in {
    imports = [
      inputs.optnix.homeModules.optnix
    ];

    programs.optnix = {
      enable = true;

      settings = {
        scopes.home-manager = {
          description = "home-manager configuration for all systems";
          options-list-file = optnixLib.hm.mkOptionsListFromHMSource {
            inherit (inputs) home-manager;
            modules = with inputs; [
              optnix.homeModules.optnix
              nix-index-database.homeModules.nix-index
            ];
          };
        };
      };
    };
  };

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
