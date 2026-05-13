{
  inputs,
  pkgs,
  perSystem,
  flake,
  ...
}: {
  imports = [
    inputs.handy.homeManagerModules.default
    flake.homeModules.noctalia
    flake.homeModules.satellite-wallpaper
    ./niri-settings.nix
  ];

  # Speech to text
  services.handy.enable = true;

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
  };

  home.packages =
    [perSystem.giopkgs.niri]
    ++ (with pkgs; [
      nautilus
      xwayland-satellite
      libnotify
      wl-clipboard
      swayidle
      brightnessctl
      slurp # Allow selecting screen area (returns geometry)
      grim # Takes screenshots
      satty # Screenshot annotation
      xdg-user-dirs # Easily get XDG dirs inside scripts
      wtype # For handy to type text
    ]);
}
