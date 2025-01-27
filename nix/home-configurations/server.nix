{ ezModules, ... }:
{
  imports = [
    ezModules.git
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
