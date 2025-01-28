{ pkgs, ezModules, ... }:
{
  imports = [
    ezModules.git
    ezModules.neovim
    ezModules.wezterm
    ezModules.qutebrowser
    ezModules.zellij
    ezModules.starship
    ezModules.zsh
    ezModules.nushell
    ezModules.hyprland
    ezModules.sway
    ezModules.waybar
    ezModules.nix-index
    ezModules.syncthing
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
