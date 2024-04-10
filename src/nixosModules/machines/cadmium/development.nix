{root, ...}: {pkgs, ...}: let
  spotify-qute = root.packages.spotify-qute {inherit pkgs;};
in {
  environment.systemPackages = with pkgs; [
    devenv
    jetbrains.datagrip
    spotify-qute
  ];
}
