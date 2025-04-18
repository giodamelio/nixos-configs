{flake, ...}: {
  imports = [
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
}
