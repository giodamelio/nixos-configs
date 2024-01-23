{root, ...}: {pkgs, ...}: {
  imports = [
    root.homeModules.modern-coreutils
    root.homeModules.git
    root.homeModules.neovim
    root.homeModules.zsh
    root.homeModules.kitty

    # Window Managers
    root.homeModules.hyprland
    root.homeModules.sway

    # Bars
    root.homeModules.waybar

    root.homeModules.nix-index
    root.homeModules.earth-desktop-background
  ];

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.05";
  };

  programs.home-manager.enable = true;

  # Setup fonts
  fonts = {
    fontconfig.enable = true;
  };
  home.packages = [
    # Ubuntu default font
    pkgs.ubuntu_font_family

    # Jetbrains Mono
    pkgs.jetbrains-mono

    # Add Inconsolata Nerdfont
    (pkgs.nerdfonts.override {
      fonts = ["Inconsolata" "JetBrainsMono"];
    })
  ];
}
