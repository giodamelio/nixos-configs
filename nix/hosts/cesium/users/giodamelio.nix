{flake, ...}: {
  imports = [
    flake.homeModules.required
    flake.homeModules.lil-scripts
    flake.homeModules.modern-coreutils-replacements
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.zellij
    flake.homeModules.starship
    flake.homeModules.zsh
    flake.homeModules.nushell
    flake.homeModules.nix-index
    flake.homeModules.atuind
    flake.homeModules.claude-code
    flake.homeModules.jj
    flake.homeModules.wezterm
    flake.homeModules.niri
    flake.homeModules.noctalia
    flake.homeModules.kde-connect
    flake.homeModules.satellite-wallpaper
  ];

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.11";
  };

  gio.role = "desktop";

  programs.home-manager.enable = true;

  # Configure Claude Code
  programs.gio-claude-code = {
    enable = true;
    installPackage = true;
  };

  # Configure nix-activate for NixOS
  gio.nix-activate-config.activation = {system = "nixos";};
}
