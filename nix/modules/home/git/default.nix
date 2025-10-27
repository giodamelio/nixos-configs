{pkgs, ...}: {
  imports = [
    ./aliases.nix
  ];

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Giovanni d'Amelio";
        email = "gio@damelio.net";
      };

      # New branch name for default inits
      init.defaultBranch = "main";
    };

    # Setup Git Large File Storage
    lfs.enable = true;

    # Add some global gitignores
    ignores = [
      "tmp/"
      ".direnv/"
      ".aider*"
    ];

    includes = [
      {path = "~/.gitconfig.extra";}
    ];
  };

  # Language aware diffing powered by Treesitter
  programs.difftastic = {
    enable = true;
    git.enable = true;
  };

  # Install Git Absorb for easy automatic fixups
  home.packages = [
    pkgs.git-absorb
  ];
}
