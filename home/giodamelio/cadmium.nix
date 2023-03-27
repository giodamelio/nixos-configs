{ inputs, pkgs, lib, config, ... }: {
  imports = [
    ./features/cli
    ./features/neovim
    ./features/hyprland
  ];

  programs = {
    home-manager.enable = true;
  };

  home = {
    username = lib.mkDefault "giodamelio";
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    stateVersion = lib.mkDefault "22.05";
    sessionPath = [ "$HOME/.local/bin" ];
  };
}
