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

      {
        config.vim = {
          keybindingTree = {
            keys = {
              "K" = {
                desc = "Show hover docs";
                lua = "vim.lsp.buf.hover()";
              };
            };

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
                  "/" = {
                    desc = "Toggle terminal";
                    mode = ["n" "t"];
                    lua = "snacks.terminal.toggle()";
                  };
                  "`" = {
                    desc = "Open explorer";
                    lua = "snacks.explorer.open()";
                  };
                };

                groups = {
                  "f" = {
                    desc = "Find";
                    keys = {
                      "f" = {
                        desc = "Files";
                        lua = "snacks.picker.smart()";
                      };
                      "h" = {
                        desc = "Hidden files";
                        lua = ''
                          snacks.picker.files({
                            finder = 'files',
                            format = 'file',
                            show_empty = true,
                            hidden = true,
                            ignored = true,
                            follow = false,
                            supports_live = true,
                          })
                        '';
                      };
                      "?" = {
                        desc = "Help tags";
                        lua = "snacks.picker.help()";
                      };
                      "b" = {
                        desc = "Buffers";
                        lua = "snacks.picker.buffers()";
                      };
                      "g" = {
                        desc = "Grep content";
                        lua = "snacks.picker.grep()";
                      };
                      "m" = {
                        desc = "Marks";
                        lua = "snacks.picker.marks()";
                      };
                      "r" = {
                        desc = "Recent files";
                        lua = "snacks.picker.recent()";
                      };
                    };
                  };

                  "c" = {
                    desc = "Claude Code";
                    defaults = {lua = false;};
                    keys = {
                      "c" = {
                        desc = "Toggle Claude";
                        cmd = "<cmd>ClaudeCode<cr>";
                      };
                      "f" = {
                        desc = "Focus Claude";
                        cmd = "<cmd>ClaudeCodeFocus<cr>";
                      };
                      "r" = {
                        desc = "Resume Claude";
                        cmd = "<cmd>ClaudeCode --resume<cr>";
                      };
                      "C" = {
                        desc = "Continue Claude";
                        cmd = "<cmd>ClaudeCode --continue<cr>";
                      };
                      "m" = {
                        desc = "Select model";
                        cmd = "<cmd>ClaudeCodeSelectModel<cr>";
                      };
                      "b" = {
                        desc = "Add buffer";
                        cmd = "<cmd>ClaudeCodeAdd %<cr>";
                      };
                      "a" = {
                        desc = "Accept diff";
                        cmd = "<cmd>ClaudeCodeDiffAccept<cr>";
                      };
                      "d" = {
                        desc = "Deny diff";
                        cmd = "<cmd>ClaudeCodeDiffDeny<cr>";
                      };
                      "s" = {
                        desc = "Send selection";
                        mode = ["v"];
                        cmd = "<cmd>ClaudeCodeSend<cr>";
                      };
                    };
                  };
                };
              };
            };
          };

          lsp.enable = true;

          theme = {
            enable = true;
            name = "tokyonight";
            style = "moon";
          };

          luaConfigPre = ''
            local snacks = require('snacks')
          '';

          languages = {
            nix.enable = true;
          };

          utility.smart-splits = {
            enable = true;
          };

          utility.snacks-nvim = {
            enable = true;
            setupOpts = {
              dashboard = {
                pane_gap = 4;
                preset = {
                  keys = [
                    {
                      icon = " ";
                      key = "f";
                      desc = "Find File";
                      action = ":lua Snacks.dashboard.pick('files')";
                    }
                    {
                      icon = " ";
                      key = "n";
                      desc = "New File";
                      action = ":ene | startinsert";
                    }
                    {
                      icon = " ";
                      key = "g";
                      desc = "Find Text";
                      action = ":lua Snacks.dashboard.pick('live_grep')";
                    }
                    {
                      icon = " ";
                      key = "r";
                      desc = "Recent Files";
                      action = ":lua Snacks.dashboard.pick('oldfiles')";
                    }
                    {
                      icon = " ";
                      key = "c";
                      desc = "Config";
                      action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.expand('$HOME/nixos-configs/nix/packages/neovim')})";
                    }
                    {
                      icon = " ";
                      key = "s";
                      desc = "Restore Session";
                      section = "session";
                    }
                    {
                      icon = " ";
                      key = "q";
                      desc = "Quit";
                      action = ":qa";
                    }
                  ];
                };
                sections = [
                  {section = "header";}
                  {
                    section = "keys";
                    gap = 1;
                    padding = 1;
                  }
                  {
                    pane = 2;
                    icon = " ";
                    title = "Recent Files";
                    section = "recent_files";
                    indent = 2;
                    padding = 1;
                  }
                  # TODO: enable this if we ever switch over to using the Lazy plugin loader
                  # { pane = 2; title = "Sessions"; section = "sessions"; indent = 2; padding = 1; }
                  {
                    pane = 2;
                    icon = " ";
                    title = "Projects";
                    section = "projects";
                    indent = 2;
                    padding = 1;
                  }
                  {
                    pane = 2;
                    icon = " ";
                    title = "Git Status";
                    section = "terminal";
                    enabled.__raw = "function() return snacks.git.get_root() ~= nil end";
                    cmd = "git status --short --branch --renames";
                    height = 5;
                    padding = 1;
                    ttl = 300;
                    indent = 3;
                  }
                  # TODO: Enable this if we ever switch to Lazy plugin loader (which I want to look into)
                  # { section = "startup"; }
                ];
              };
            };
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
