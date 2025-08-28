{
  inputs,
  pkgs,
  ...
}: let
  inherit (pkgs) lib;
  # inherit (lib.nvim.binds) mkKeymap mkLuaBinding;
  # pretty = val: lib.trace (lib.generators.toPretty {multiline = true;} val) val;
in
  (inputs.nvf.lib.neovimConfiguration {
    inherit pkgs;

    modules = [
      ./keybinding-tree.nix
      ./git.nix
      ./autocomplete.nix
      ./treesitter.nix
      ./lsp.nix
      ./finding.nix
      ./claude-code.nix
      ./lualine.nix

      {
        config.vim = {
          # Use space as the leader key and , as the localleader
          globals.mapleader = " ";
          globals.maplocalleader = ",";

          options = {
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

            # File change detection - reload files when they change on disk
            autoread = true; # Automatically read file when changed outside vim
            updatetime = 100; # Faster update time (default is 4000ms)
          };

          keybindingTree = {
            groups = {
              "<leader>" = {
                desc = "Leader";
                defaults = {
                  mode = ["n"];
                  silent = true;
                  lua = true;
                };

                keys = {
                  "<Tab>" = {
                    desc = "Switch to last buffer";
                    cmd = "<cmd>edit #<cr>";
                  };
                };
              };
            };
          };

          theme = {
            enable = true;
            name = "tokyonight";
            style = "moon";
          };

          languages = {
            nix.enable = true;
            lua.enable = true;
          };

          utility.smart-splits = {
            enable = true;
          };

          luaConfigPost = ''
            -- File-type specific keybindings

            -- Lua-specific keybindings
            vim.api.nvim_create_autocmd('FileType', {
              pattern = 'lua',
              callback = function()
                vim.keymap.set({'n', 'v'}, '<localleader>e', '<cmd>LuaEval<cr>', {
                  desc = 'Evaluate current file/selection',
                  buffer = true
                })
              end,
            })

            -- Claude Code file browser specific keybindings
            vim.api.nvim_create_autocmd('FileType', {
              pattern = { 'NvimTree', 'neo-tree', 'oil', 'minifiles' },
              callback = function()
                vim.keymap.set('n', '<leader>cs', '<cmd>ClaudeCodeTreeAdd<cr>', {
                  desc = 'Add file',
                  buffer = true
                })
                vim.keymap.set('n', '<leader>cS', function()
                  vim.cmd('ClaudeCodeTreeAdd')
                  vim.cmd('ClaudeCodeFocus')
                  -- Wait 100ms for focus to complete, then send enter
                  vim.defer_fn(function()
                    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
                  end, 100)
                end, {
                  desc = 'Add file and send',
                  buffer = true
                })
              end,
            })
          '';
        };
      }
    ];
  }).neovim
