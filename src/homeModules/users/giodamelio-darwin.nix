{root, ...}: {pkgs, ...}: {
  imports = [
    root.homeModules.users.giodamelio

    root.homeModules.git
    root.homeModules.neovim
    root.homeModules.kitty
    root.homeModules.wezterm
    root.homeModules.qutebrowser

    root.homeModules.starship
    root.homeModules.zsh
    root.homeModules.nushell

    root.homeModules.nix-index

    # This is only necessary until I get the setup working and add it per repo
    (_: {
      programs.git.ignores = [
        "/.devenv*"
      ];
    })
  ];

  home = {
    homeDirectory = "/Users/giodamelio";
    stateVersion = "23.11";
  };

  home.packages = [
    pkgs.kitty
    pkgs.rectangle
  ];
}
