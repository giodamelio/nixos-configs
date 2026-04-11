{perSystem, ...}: {
  programs.wezterm = {
    enable = true;
    package = perSystem.giopkgs.wezterm;
    enableZshIntegration = true;
    extraConfig = builtins.readFile ./wezterm.lua;
  };
}
