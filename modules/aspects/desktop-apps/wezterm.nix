# wezterm — terminal emulator. Converted from nix/modules/home/wezterm.nix; the
# Lua config is copied alongside this aspect as ./wezterm.lua and the package is
# reached as `perSystem.giopkgs.wezterm`.
_: {
  den.aspects.wezterm.homeManager = {perSystem, ...}: {
    programs.wezterm = {
      enable = true;
      package = perSystem.giopkgs.wezterm;
      enableZshIntegration = true;
      extraConfig = builtins.readFile ./wezterm.lua;
    };
  };
}
