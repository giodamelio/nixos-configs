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
      ./lsp.nix
      ./finding.nix
      ./claude-code.nix

      {
        config.vim = {
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
