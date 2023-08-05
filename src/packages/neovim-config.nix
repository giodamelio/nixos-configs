{debug, ...}: {pkgs, ...}: let
  lib = pkgs.lib;
in
  pkgs.stdenv.mkDerivation {
    name = "neovim-config";
    src = ./neovim-config-src;

    # Export Lazy.nvim so it can be loaded first
    lazyvim = pkgs.vimPlugins.lazy-nvim;

    # Put symlinks to all the other plugins in one big directory
    allThePlugins = let
      makeEntryFromDrv = drv: {
        name = let
          removeNCharFromEnd = str: n: builtins.substring 0 ((builtins.stringLength str) - n) str;
          removePrefix = name:
            lib.pipe name [
              (n: lib.strings.removePrefix "vimplugin-" n)
              (n: lib.strings.removePrefix "lua5.1-" n)
            ];
          removeSuffix = name: removeNCharFromEnd name 11;
        in
          lib.pipe drv.name [removePrefix removeSuffix];
        path = drv;
      };

      # Plugins from Nixpkgs
      plugins = with pkgs.vimPlugins; [
        plenary-nvim
        tokyonight-nvim
        vim-eunuch
        bufdelete-nvim
        which-key-nvim
        telescope-nvim

        # LSP + Completion + Snippets
        nvim-lspconfig
        nvim-cmp
        cmp-nvim-lsp
        cmp-buffer
        cmp-path
        cmp-cmdline
        luasnip
        cmp_luasnip
        friendly-snippets

        nvim-treesitter.withAllGrammars
        lualine-nvim
        lualine-lsp-progress
        nvim-web-devicons
        trouble-nvim
        nvim-navic
        oil-nvim
        gitsigns-nvim
        comment-nvim
        marks-nvim
        neogit
        ChatGPT-nvim
        nui-nvim
      ];

      # Some plugins I need different versions then NixPkgs has
      customPlugins = [
        # Not yet packaged
        (pkgs.vimUtils.buildVimPluginFrom2Nix {
          pname = "rainbow-delimiters.nvim";
          version = "2023-08-03";
          src = pkgs.fetchFromGitHub {
            owner = "hiphish";
            repo = "rainbow-delimiters.nvim";
            rev = "c6380e218a2b4ffcc957a71606900a24e5c7b618"; # Latest on branch master as of 2023-08-03
            hash = "sha256-FIenPsoplMt9yYFTCrkfHWWMHRIUTxE8cFwEYM/RHOQ=";
          };
          meta.homepage = "https://github.com/hiphish/rainbow-delimiters.nvim";
        })

        # Fork of ruifm/gitlinker.nvim, not yet packaged
        (pkgs.vimUtils.buildVimPluginFrom2Nix {
          pname = "gitlinker.nvim";
          version = "2023-08-03";
          src = pkgs.fetchFromGitHub {
            owner = "linrongbin16";
            repo = "gitlinker.nvim";
            rev = "bc1c6801b4771d6768c6ec6727d0e7669e6aac5f"; # Latest on branch master as of 2023-08-03
            hash = "sha256-GnqXK9PW4dxWVvQnOerPMQ+XKZzGL8ozlYs1/3PWFjc=";
          };
          meta.homepage = "https://github.com/linrongbin16/gitlinker.nvim";
        })

        # Not yet packaged
        (pkgs.vimUtils.buildVimPluginFrom2Nix {
          pname = "stay-centered.nvim";
          version = "2023-08-03";
          src = pkgs.fetchFromGitHub {
            owner = "arnamak";
            repo = "stay-centered.nvim";
            rev = "0715638e7110362f95ead35c290fcd040c2d2735"; # Latest on branch master as of 2023-08-03
            hash = "sha256-iaaWmXtgTPr3zecWD94D5PVB1yanpEb+oH4R2ukTT+A=";
          };
          meta.homepage = "https://github.com/arnamak/stay-centered.nvim";
        })
      ];
    in
      pkgs.linkFarm
      "vim-plugins-bundle"
      (map makeEntryFromDrv (plugins ++ customPlugins));

    installPhase = ''
      mkdir $out
      substituteAllInPlace init.lua
      substituteAllInPlace lua/plugins.lua
      cp -R * $out/
    '';
  }
