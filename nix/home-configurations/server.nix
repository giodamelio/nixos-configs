{ezModules, ...}: {
  imports = [
    ezModules.git
    ezModules.neovim
    ezModules.zsh
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
