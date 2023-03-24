{ pkgs, lib, config, ... }: {
  programs.fish = {
    enable = true;
    shellAbbrs = {
      ls = "exa";
      ll = "exa -l";
      la = "exa -la";
      tree = "exa --tree";
    };
    functions = {
      fish_greeting = "";
    };
  };
}
