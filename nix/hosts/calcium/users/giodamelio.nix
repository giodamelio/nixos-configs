{flake, ...}: {
  imports = [
    flake.homeModules.required
    flake.homeModules.modern-coreutils-replacements
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.zellij
    flake.homeModules.starship
    flake.homeModules.zsh
    flake.homeModules.nushell
    flake.homeModules.nix-index
    flake.homeModules.atuind
    flake.homeModules.llm
  ];

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.11";
  };

  programs.home-manager.enable = true;

  # Configure nix-activate for NixOS-WSL
  gio.nix-activate-config.activation = {system = "nixos";};
}
