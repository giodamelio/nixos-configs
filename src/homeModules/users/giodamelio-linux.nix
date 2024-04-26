{root, ...}: _: {
  imports = [
    root.homeModules.users.giodamelio

    root.homeModules.modern-coreutils
    root.homeModules.git
    root.homeModules.neovim
    root.homeModules.kitty
    root.homeModules.wezterm
    root.homeModules.helix

    root.homeModules.starship
    root.homeModules.zsh
    root.homeModules.nushell

    # Window Managers
    root.homeModules.hyprland
    root.homeModules.sway

    # Bars
    root.homeModules.waybar

    root.homeModules.nix-index
    root.homeModules.syncthing
  ];

  home = {
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.05";
  };
}
