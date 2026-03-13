{
  inputs,
  pkgs,
  ...
}: let
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
}
