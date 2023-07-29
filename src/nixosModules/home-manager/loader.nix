{inputs, ...}: {
  config,
  lib,
  pkgs,
  ...
}: let
  home-manager = inputs.home-manager;
in {
  imports = [
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    }
  ];
}
