_: _: {
  programs.starship = {
    enable = true;
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
        shell = {
          disabled = false;
        };
      }
      // (builtins.fromTOML (builtins.readFile ./starship-nerdfont.toml));
  };
}
