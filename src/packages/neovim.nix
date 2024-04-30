_: {pkgs, ...}: let
  rainbowDelimitersNvim = pkgs.vimUtils.buildVimPlugin {
    pname = "rainbow-delimiters.nvim";
    version = "2023-12-15";
    src = pkgs.fetchFromGitLab {
      owner = "HiPhish";
      repo = "rainbow-delimiters.nvim";
      rev = "0b4c1ab6724062f3582746c6a5a8c0636bf7ed81";
      hash = "sha256-LV/kFqq0e4/208cN6B2R+ECvpGG4MUsfPIZsk/up53c=";
    };
    meta.homepage = "https://github.com/hiphish/rainbow-delimiters.nvim";
  };

  gitlinker = pkgs.vimUtils.buildVimPlugin {
    pname = "gitlinker.nvim";
    version = "2023-12-15";
    src = pkgs.fetchFromGitHub {
      owner = "linrongbin16";
      repo = "gitlinker.nvim";
      rev = "bc1c6801b4771d6768c6ec6727d0e7669e6aac5f"; # Latest on branch master as of 2023-12-15
      hash = "sha256-GnqXK9PW4dxWVvQnOerPMQ+XKZzGL8ozlYs1/3PWFjc=";
    };
    meta.homepage = "https://github.com/linrongbin16/gitlinker.nvim";
  };

  stayCentered = pkgs.vimUtils.buildVimPlugin {
    pname = "stay-centered.nvim";
    version = "2023-12-15";
    src = pkgs.fetchFromGitHub {
      owner = "arnamak";
      repo = "stay-centered.nvim";
      rev = "0715638e7110362f95ead35c290fcd040c2d2735"; # Latest on branch master as of 2023-12-15
      hash = "sha256-iaaWmXtgTPr3zecWD94D5PVB1yanpEb+oH4R2ukTT+A=";
    };
    meta.homepage = "https://github.com/linrongbin16/gitlinker.nvim";
  };

  ChatGPT = pkgs.vimUtils.buildVimPlugin {
    pname = "ChatGPT.nvim";
    version = "2024-02-21";
    src = pkgs.fetchFromGitHub {
      owner = "jackMort";
      repo = "ChatGPT.nvim";
      rev = "aadb607038d53d97be4da368b07355f65ad3f047";
      hash = "sha256-nIaOjwXBJJTKooyvtjIQIyoFCvZM0vOxhzwZRwBjLOo=";
    };
    meta.homepage = "https://github.com/jackMort/ChatGPT.nvim";
  };

  nvimConfig = pkgs.neovimUtils.makeNeovimConfig {
    withPython3 = true;
    vimAlias = true;
    viAlias = true;

    plugins = with pkgs.vimPlugins; [
      # Colorscheme
      {
        plugin = tokyonight-nvim;
        config = "colorscheme tokyonight";
      }

      # Interactivly show keybinds
      which-key-nvim

      # Pretty lists of things
      trouble-nvim

      # Fuzzy find things
      telescope-nvim
      plenary-nvim # Needed dependency

      # Language Server
      nvim-lspconfig

      # Autocomplete
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline

      # Snippets
      luasnip
      cmp_luasnip
      friendly-snippets

      # Code Context
      nvim-navic

      # AST for hightlighting, formatting, etc
      nvim-treesitter.withAllGrammars
      rainbowDelimitersNvim # Rainbow parens
      nvim-treesitter-parsers.hurl

      # Status bar
      lualine-nvim
      lualine-lsp-progress
      nvim-web-devicons

      # Git stuff
      gitsigns-nvim # Git status in the gutter
      gitlinker # Easily link to specific file locations
      neogit # Git ui

      # Test running
      neotest
      nvim-nio # Needed dependency
      neotest-rust
      neotest-elixir
      neotest-go
      neotest-deno

      # ChatGPT-nvim # ChatGPT integration
      ChatGPT # ChatGPT integration
      nui-nvim # needed for ChatGPT
      oil-nvim # Move/Create/Delete files/directories directly in a vim buffer
      nvim-surround # Deal with pairs of things
      comment-nvim # Better comments
      marks-nvim # Show marks in the sign column
      vim-eunuch # Do a Unix to it
      bufdelete-nvim # Better behaved :Bedelete (keeps splits etc...)
      stayCentered # Keep the cursor line centered vertically as much as possible
      vim-startuptime # Keep on top of Neovim startup time
    ];

    customRC = "
      luafile ${./_neovim_lua/basic.lua}
      luafile ${./_neovim_lua/lsp.lua}
      luafile ${./_neovim_lua/treesitter.lua}
      luafile ${./_neovim_lua/plugins.lua}
      luafile ${./_neovim_lua/keybinds.lua}
    ";
  };
in
  pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped nvimConfig
