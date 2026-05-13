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
}
