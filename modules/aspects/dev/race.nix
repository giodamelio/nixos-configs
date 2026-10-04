_: {
  den.aspects.race.homeManager = {
    perSystem,
    pkgs,
    ...
  }: {
    home.packages = [perSystem.giopkgs.race];

    xdg.configFile."race/config.toml".source = (pkgs.formats.toml {}).generate "race-config.toml" {
      # Super alone collides with niri's Mod binds, and Ctrl/Alt combos reach programs inside the terminals
      keyboard.prefix = "Cmd-Alt";

      # Arrows instead of H/J/K/L, which niri already binds on Mod+Alt and Mod+Shift+Alt
      keyboard.shortcuts = {
        focus-left = "Prefix-Left";
        focus-down = "Prefix-Down";
        focus-up = "Prefix-Up";
        focus-right = "Prefix-Right";
        new-terminal-left = "Prefix-Shift-Left";
        new-terminal-down = "Prefix-Shift-Down";
        new-terminal-up = "Prefix-Shift-Up";
        new-terminal-right = "Prefix-Shift-Right";
      };
    };
  };
}
