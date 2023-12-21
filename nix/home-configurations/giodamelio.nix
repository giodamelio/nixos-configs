{...}: {
  programs.eza.enable = true;
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "Giovanni d'Amelio";
    userEmail = "gio@damelio.net";
  };

  home = {
    username = "giodamelio";
    homeDirectory = "/home/giodamelio";
    stateVersion = "24.05";
  };
}
