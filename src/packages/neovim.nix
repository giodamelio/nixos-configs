_: {pkgs, ...}: let
  gitlinker = pkgs.vimUtils.buildVimPlugin {
    pname = "gitlinker.nvim";
    version = "2023-12-15";
    src = pkgs.fetchFromGitHub {
      owner = "linrongbin16";
      repo = "gitlinker.nvim";
      rev = "542f51784f20107ef9ecdadc47825204837efed5"; # Latest on branch master as of 2024-06-26
      hash = "sha256-OnlJf31dTzLOJ1tlDKH7slPnQGMZUloavEAtd/FxK0U=";
    };
    meta.homepage = "https://github.com/linrongbin16/gitlinker.nvim";
  };

  stayCentered = pkgs.vimUtils.buildVimPlugin {
    pname = "stay-centered.nvim";
    version = "2023-12-15";
    src = pkgs.fetchFromGitHub {
      owner = "arnamak";
      repo = "stay-centered.nvim";
      rev = "91113bd82ac34f25c53d53e7c1545cb5c022ade8"; # Latest on branch main as of 2024-06-26
      hash = "sha256-DDhF/a8S7Z1aR1Hg8UVgttl3je0hhn/OpZoakOeMHQw=";
    };
    meta.homepage = "https://github.com/arnamak/stay-centered.nvim";
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
      rainbow-delimiters-nvim # Rainbow parens
      nvim-treesitter-parsers.hurl

      # Status bar
      lualine-nvim
      lualine-lsp-progress
      nvim-web-devicons

      # Git stuff
      gitsigns-nvim # Git status in the gutter
      gitlinker # Easily link to specific file locations
      neogit # Git ui
      diffview-nvim # Better diffs

      # Test running
      neotest
      nvim-nio # Needed dependency
      neotest-rust
      neotest-elixir
      neotest-go
      neotest-deno

      # ChatGPT-nvim # ChatGPT integration
      ChatGPT-nvim # ChatGPT integration
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
