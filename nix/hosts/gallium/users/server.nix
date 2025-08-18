{flake, ...}: {
  imports = [
    flake.homeModules.required
    flake.homeModules.git
    flake.homeModules.neovim
    flake.homeModules.zsh
    flake.homeModules.atuin
  ];

  home = {
    username = "server";
    homeDirectory = "/home/server";
    stateVersion = "25.05";
  };

  programs.git = {
    enable = true;
  };

  # Configure nix-activate for NixOS
  gio.nix-activate-config.activation = {system = "nixos";};
}
