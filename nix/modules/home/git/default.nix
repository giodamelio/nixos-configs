{pkgs, ...}: {
  imports = [
    ./aliases.nix
  ];

  programs.git = {
    # Use Difftastic for language aware diffing powered by Treesitter
    difftastic.enable = true;

    # Setup Git Large File Storage
    lfs.enable = true;

    # Add some global gitignores
    ignores = [
      "tmp/"
      ".direnv/"
      ".aider*"
    ];
  };

  # Install Git Absorb for easy automatic fixups
  home.packages = [
    pkgs.git-absorb
  ];
}
