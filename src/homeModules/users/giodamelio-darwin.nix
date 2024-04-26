{root, ...}: {pkgs, ...}: {
  imports = [
    root.homeModules.users.giodamelio

    root.homeModules.modern-coreutils
    root.homeModules.git
    root.homeModules.neovim
    root.homeModules.kitty

    root.homeModules.starship
    root.homeModules.zsh
    root.homeModules.nushell
  ];

  home = {
    homeDirectory = "/Users/giodamelio";
    stateVersion = "23.11";
  };

  home.packages = [
    pkgs.raycast
    pkgs.kitty
    pkgs.rectangle
  ];
}
