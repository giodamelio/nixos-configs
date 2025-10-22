{flake, ...}: {
  imports = [
    flake.homeModules.required
    flake.homeModules.lil-scripts
    flake.homeModules.modern-coreutils-replacements
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
    flake.homeModules.atuind
    flake.homeModules.claude-code
  ];

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.11";
  };

  programs.home-manager.enable = true;

  # Configure nix-activate for NixOS
  gio.nix-activate-config.activation = {system = "nixos";};

  # Configure Claude Code
  programs.claude-code = {
    enable = true;
    installPackage = true;
  };

  # Setup fonts
  fonts = {
    fontconfig.enable = true;
  };
}
