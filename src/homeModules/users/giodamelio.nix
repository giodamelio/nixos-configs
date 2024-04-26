_: {pkgs, ...}: {
  home = {
    username = "giodamelio";
  };

  programs.home-manager.enable = true;

  # Setup fonts
  fonts = {
    fontconfig.enable = true;
  };
  home.packages = [
    # Ubuntu default font
    pkgs.ubuntu_font_family

    # Jetbrains Mono
    pkgs.jetbrains-mono

    # Add Inconsolata Nerdfont
    (pkgs.nerdfonts.override {
      fonts = ["Inconsolata" "JetBrainsMono"];
    })
  ];
}
