{pkgs, ...}: let
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

  tresitterGrammerSurrealdb = pkgs.tree-sitter.buildGrammar {
    language = "surrealdb";
    version = "2025-09-24";
    src = pkgs.fetchFromGitHub {
      owner = "DariusCorvus";
      repo = "tree-sitter-surrealdb";
      # Latest on branch main as of 2025-09-24
      rev = "17a7ed4481bdaaa35a1372f3a94bc851d634a19e";
      hash = "sha256-/xX5lEQKFuLQl6YxUA2WLKGX5P2GBugtYj42WCtA0xU=";
    };
  };

  surrealdbTreesitter = pkgs.vimUtils.buildVimPlugin {
    pname = "tree-sitter-surrealdb.nvim";
    version = "2025-09-24";
    src = pkgs.fetchFromGitHub {
      owner = "DariusCorvus";
      repo = "tree-sitter-surrealdb.nvim";
      # Latest on branch main as of 2025-09-24
      rev = "a875cb4be3035a0cb525c35c4c6f1512fb9fa27d";
      hash = "sha256-hEkIX7oCLhw+fNp7xzwZ2sCrDWWhM6nbrY7O4L2HYZE=";
    };
    meta.homepage = "https://github.com/DariusCorvus/tree-sitter-surrealdb.nvim";
  };

  nvimConfig = pkgs.neovimUtils.makeNeovimConfig {
    withPython3 = true;
    withRuby = false;
    vimAlias = true;
    viAlias = true;

    plugins = with pkgs.vimPlugins; [
      # Colorscheme
      {
        plugin = tokyonight-nvim;
        config = "colorscheme tokyonight";
      }

      # Icons
      nvim-web-devicons
      mini-icons
      lspkind-nvim

      # Interactivly show keybinds
      which-key-nvim

      # Pretty lists of things
      trouble-nvim

      # Lots of things need this
      plenary-nvim

      # Language Server
      nvim-lspconfig

      # Autocomplete
      blink-cmp
      blink-cmp-git

      # Snippets
      luasnip
      friendly-snippets

      # Code Context
      nvim-navic

      # AST for hightlighting, formatting, etc
      # All grammers plus my added one
      (nvim-treesitter.withPlugins (_: nvim-treesitter.allGrammars ++ [tresitterGrammerSurrealdb]))
      rainbow-delimiters-nvim # Rainbow parens
      nvim-treesitter-parsers.hurl
      surrealdbTreesitter

      # Status bar
      lualine-nvim
      lualine-lsp-progress

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
      neotest-rspec

      avante-nvim # GenAI addition
      oil-nvim # Move/Create/Delete files/directories directly in a vim buffer
      comment-nvim # Better comments
      marks-nvim # Show marks in the sign column
      vim-eunuch # Do a Unix to it
      bufdelete-nvim # Better behaved :Bedelete (keeps splits etc...)
      stayCentered # Keep the cursor line centered vertically as much as possible
      vim-startuptime # Keep on top of Neovim startup time
      elixir-tools-nvim # Elixir tooling
      other-nvim # Easily switch to related file types
      nvim-notify # Pretty notifications
      claudecode-nvim # Integration with Claude Code
      smart-splits-nvim # Easy Multiplexer Split Navigation
      snacks-nvim # Collection of small quality of life plugins by Folke
      persisted-nvim # Session manager
      mini-ai # Better a/i text objects
      firenvim # Use Neovim in the browser
      vim-dadbod # Interact with databases
    ];

    customRC = "
      luafile ${./lua/basic.lua}
      luafile ${./lua/lsp.lua}
      luafile ${./lua/treesitter.lua}
      luafile ${./lua/plugins.lua}
      luafile ${./lua/commands.lua}
      luafile ${./lua/keybinds.lua}
      luafile ${./lua/neovide.lua}
    ";
  };
in
  pkgs.symlinkJoin {
    name = "nvim";
    meta.mainProgram = "nvim";
    paths = [
      # Custom Neovim
      (pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped nvimConfig)

      # Some random dependencies
      pkgs.imagemagick # Snacks: For inline images
    ];
  }
