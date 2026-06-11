# starship — prompt config. Converted from nix/modules/home/starship/default.nix;
# the nerd-font preset TOML is copied alongside this aspect as
# ./starship-nerdfont.toml.
_: {
  den.aspects.starship.homeManager = {
    programs.starship = {
      enable = true;
      settings =
        {
          format = "$all\${env_var.ZMX_SESSION}$fill $time\n$character";
          env_var.ZMX_SESSION = {
            symbol = "🪟 ";
            format = "[$symbol$env_value]($style) ";
            description = "zmx session name";
            style = "bold magenta";
          };
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
  };
}
