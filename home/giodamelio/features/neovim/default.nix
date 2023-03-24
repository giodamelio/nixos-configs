{ pkgs, ... }: {
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

  home.packages = with pkgs; [
    # Install some language servers
    sumneko-lua-language-server # Lua
  ];
}
