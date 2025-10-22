{flake, ...}: {
  imports = [
    flake.homeModules.required
    flake.homeModules.lil-scripts
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.zsh
    flake.homeModules.atuin
  ];

  home = {
    username = "server";
    homeDirectory = "/home/server";
    stateVersion = "24.11";
  };

  programs.git = {
    enable = true;
  };

  # Configure nix-activate for NixOS
  gio.nix-activate-config.activation = {system = "nixos";};
}
