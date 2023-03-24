{ pkgs, lib, config, ... }: {
  programs.starship = {
    enable = true;
    settings = {
      format = "$all$fill $time$line_break$character";
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
    };
  };
}
