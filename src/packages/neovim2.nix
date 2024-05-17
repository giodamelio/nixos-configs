{inputs, ...}: {
  pkgs,
  inputs',
  system,
  ...
}: let
  # Update the Neovim Version
  neovim_010_overlay = _: super: {
    neovim-unwrapped = super.neovim-unwrapped.overrideAttrs (_: rec {
      version = "0.10.0";

      src = pkgs.fetchFromGitHub {
        owner = "neovim";
        repo = "neovim";
        rev = "v${version}";
        hash = "sha256-FCOipXHkAbkuFw9JjEpOIJ8BkyMkjkI0Dp+SzZ4yZlw=";
      };
    });
  };

  # Copy of Nixpkgs with Neovim version overridden
  pkgsWithOverlay = import inputs.nixpkgs {
    inherit system;
    overlays = [neovim_010_overlay];
  };
in
  inputs'.nixvim.legacyPackages.makeNixvim {
    # Use our updated version of Neovim 0.10.0
    package = pkgsWithOverlay.neovim-unwrapped;

    colorschemes.tokyonight.enable = true;

    # Global Variables
    globals = {
      # Set our leaders keys
      mapleader = " ";
      maplocalleader = ",";
    };

    # Basic Options
    opts = {
      # Set the default tab to 2 spaces
      tabstop = 2;
      shiftwidth = 2;
      softtabstop = 2;
      expandtab = true; # Use spaces instead of tabs

      # Show relative line numbers
      number = true;
      relativenumber = true;

      # Make search smarter
      ignorecase = true; # Case insensitive search
      smartcase = true; # If there are uppercase letters, become case-sensitive

      # Use the system clipboard by default
      clipboard = "unnamedplus";

      # Show trailing spaces as dots
      list = true;
      listchars = "trail:·,tab:  ";

      # Highlight the line the cursor is on
      cursorline = true;

      # Completely disable the mouse
      mouse = "";

      # Options for completions
      completeopt = "menu,menuone,noselect";

      # Enable 24 bit colors requires ISO-8613-3 compatible terminal
      termguicolors = true;
    };

    plugins = {
      which-key.enable = true;
      telescope.enable = true;
    };

    keymaps = [
      {
        key = "<leader>ff";
        action = ''require('telescope.builtin').find_files'';
        lua = true;
      }
    ];
  }
