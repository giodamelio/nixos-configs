{flake, ...}: let
  inherit (flake.lib.homelab.machines.cadmium) monitor-names;
in {
  imports = [
    flake.homeModules.niri
    flake.homeModules.noctalia
    flake.homeModules.satellite-wallpaper
  ];

  programs.niri.settings = {
    outputs = {
      "${monitor-names.middle}" = {
        scale = 2.0;
        position = {
          x = 1080;
          y = 420;
        };
      };
      "${monitor-names.right}" = {
        scale = 2.0;
        position = {
          x = 3000;
          y = 420;
        };
      };
      "${monitor-names.left}" = {
        scale = 2.0;
        position = {
          x = 0;
          y = 0;
        };
        transform.rotation = 90;
      };
    };
    workspaces = {
      "1" = {open-on-output = monitor-names.middle;};
      "2" = {open-on-output = monitor-names.right;};
      "3" = {open-on-output = monitor-names.left;};
    };
  };
}
