_: _: {
  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 12.0;
    };

    shellIntegration.enableZshIntegration = true;

    settings = {
      shell = "nu";
    };
  };
}
