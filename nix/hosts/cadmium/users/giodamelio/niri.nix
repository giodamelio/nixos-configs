{
  lib,
  pkgs,
  config,
  inputs,
  flake,
  ...
}: let
  singleDisplayConfig =
    inputs.niri.lib.internal.validated-config-for
    pkgs
    config.programs.niri.package
    (lib.evalModules {
      specialArgs = {inherit pkgs;};
      modules = [
        inputs.niri.lib.internal.settings-module
        flake.homeModules.niri-launcher-binds
        flake.homeModules.niri-settings
        ./niri/single-display.nix
      ];
    })
    .config
    .programs
    .niri
    .finalConfig;
in {
  imports = [
    flake.homeModules.niri
    ./niri/three-monitor.nix
  ];

  xdg.configFile."niri/single-display.kdl".source = singleDisplayConfig;

  gio.niri.binds = {
    # My old Microsoft keyboard doesn't have next/prev keys,
    # so I use "My Favorites" buttons labeled 2 and 4.
    # Those are mapped to XF86Launch6 and XF86Launch8 respectivly.
    "XF86Launch8".action.spawn = ["${lib.getExe pkgs.playerctl}" "next"];
    "XF86Launch6".action.spawn = ["${lib.getExe pkgs.playerctl}" "previous"];
  };
}
