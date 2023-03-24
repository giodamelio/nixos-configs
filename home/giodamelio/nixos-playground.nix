{ inputs, pkgs, lib, config, ... }: {
  programs = {
    home-manager.enable = true;
    gh.enable = true;
    git = {
      enable = true;
      userName = "Giovanni d'Amelio";
      userEmail = "gio@damelio.net";
      aliases = {
        ci = "commit";
        st = "status";
      };
      delta = {
        enable = true;
      };
    };
  };

  home = {
    username = lib.mkDefault "giodamelio";
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    stateVersion = lib.mkDefault "22.05";
    sessionPath = [ "$HOME/.local/bin" ];
  };
}
