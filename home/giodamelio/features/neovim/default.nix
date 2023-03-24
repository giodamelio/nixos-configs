{ pkgs, ... }: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    withPython3 = true;
  };

  home.file."neovim-config" = {
    enable = true;
    source = "${./config}";
    target = ".config/nvim/";
  };
}
