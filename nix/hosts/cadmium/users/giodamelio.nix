{
  pkgs,
  flake,
  ...
}: {
  imports = [
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.wezterm
    flake.homeModules.qutebrowser
    flake.homeModules.zellij
    flake.homeModules.starship
    flake.homeModules.zsh
    flake.homeModules.nushell
    flake.homeModules.hyprland
    flake.homeModules.sway
    flake.homeModules.waybar
    flake.homeModules.nix-index
    flake.homeModules.syncthing
  ];

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.11";
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
    pkgs.nerd-fonts.inconsolata
    pkgs.nerd-fonts.jetbrains-mono
  ];
}
