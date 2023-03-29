{ pkgs, ... }: {
  programs.kitty = {
    enable = true;
    font = {
      package = pkgs.nerdfonts;
      name = "Inconsolata";
      size = 12;
    };
  };
}
