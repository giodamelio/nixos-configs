{ezModules, ...}: {
  imports = [
    ezModules.git
  ];

  programs.eza.enable = true;
  programs.home-manager.enable = true;

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.05";
  };
}
