{ pkgs, ... }: {
  programs.kitty = {
    enable = true;
    font = {
      package = pkgs.nerdfonts;
      name = "Inconsolata";
      size = 16;
    };
  };

  home.packages = [
    (pkgs.nerdfonts.override {
      fonts = [ "Inconsolata" ];
    })
  ];
}
