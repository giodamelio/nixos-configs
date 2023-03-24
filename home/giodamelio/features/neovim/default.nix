{ pkgs, ... }:
let
  treesitter-parsers = pkgs.symlinkJoin {
    name = "treesitter-parser";
    paths = pkgs.vimPlugins.nvim-treesitter.withAllGrammars.dependencies;
  };
in {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    withPython3 = true;
    plugins = with pkgs.vimPlugins; [
      nvim-treesitter.withAllGrammars
    ];
  };

  home.file."neovim-config" = {
    enable = true;
    source = "${./config}";
    target = ".config/nvim/";
  };

  # Hack to get the path from the treesitter grammers into the Neovim runtimepath
  xdg.configFile."nvim-treesitter-runtimepath-hack.txt" = {
    text = "${treesitter-parsers}";
  };

  home.packages = with pkgs; [
    # Install some language servers
    sumneko-lua-language-server # Lua
    nil # Nix
  ];
}
