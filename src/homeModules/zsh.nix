_: _: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = [
      "--disable-up-arrow"
    ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings =
      {
        format = "$all$fill $time\n$character";
        directory = {
          truncation_length = 4;
        };
        fill = {
          symbol = ".";
          style = "#666666";
        };
        time = {
          disabled = false;
        };
        line_break = {
          disabled = true;
        };
      }
      // (builtins.fromTOML (builtins.readFile ./starship-nerdfont.toml));
  };

  programs.nnn = {
    enable = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
