{ pkgs, ... }: {
  imports = [
    ./gh.nix
    ./git.nix
  ];

  home.packages = with pkgs; [
    comma # Install and run programs by sticking a , before them
    bottom # System viewer
    ncdu # TUI disk usage
    ripgrep # Better grep
    fd # Better find
    httpie # Better curl
    jq # JSON pretty printer and manipulator
    exa # ls alternative
  ];
}
