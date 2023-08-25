{inputs, ...}: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (inputs) home-manager;
in {
  imports = [
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    }
  ];
}
