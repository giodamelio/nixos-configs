{root, ...}: {pkgs, ...}: {
  imports = [
    root.homeModules.modern-coreutils
    root.homeModules.git
    root.homeModules.neovim
    root.homeModules.zsh
    root.homeModules.kitty
    root.homeModules.hyprland
    root.homeModules.nix-index
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
    # Add Inconsolata Nerdfont
    (pkgs.nerdfonts.override {
      fonts = ["Inconsolata"];
    })
  ];
}
