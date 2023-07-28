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
      home-manager.users.server = {
        home.stateVersion = "23.11";
        programs = {
          zellij = {
            enable = true;
            settings = {
              pane_frames = false;
              ui.pane_frames.hide_session_name = true;
            };
          };
        };
      };
    }
  ];
}
