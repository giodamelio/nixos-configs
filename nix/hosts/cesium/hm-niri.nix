{flake, ...}: {
  imports = [
    flake.homeModules.niri
    flake.homeModules.noctalia
    flake.homeModules.satellite-wallpaper
  ];
}
