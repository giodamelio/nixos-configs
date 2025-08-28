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
      # Self-contained keybinding tree module
      ({
        lib,
        config,
        ...
      }: let
        inherit (lib) mkOption types mkIf;

        # Recursive keybinding node type
        keybindingNodeType = types.submodule {
          options = {
            desc = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Description for WhichKey group";
            };

            defaults = mkOption {
              type = types.submodule {
                options = {
                  mode = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                  };
                  silent = mkOption {
                    type = types.nullOr types.bool;
                    default = null;
                  };
                  lua = mkOption {
                    type = types.nullOr types.bool;
                    default = null;
                  };
                };
              };
              default = {};
              description = "Defaults for direct keys in this group";
            };

            keys = mkOption {
              type = types.attrsOf (types.addCheck (types.submodule {
                  options = {
                    desc = mkOption {
                      type = types.str;
                      description = "Key description";
                    };

                    # Mutually exclusive action types - specify exactly one
                    cmd = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = ''
                        Vim command string. Use for commands like "<cmd>edit #<cr>".
                        Mutually exclusive with lua, luaFn, and raw.
                      '';
                    };

                    lua = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = ''
                        Lua function call (auto-wrapped in function() ... end).
                        Use for simple function calls like "snacks.picker.smart()".
                        Mutually exclusive with cmd, luaFn, and raw.

                        Example: lua = "vim.lsp.buf.hover()";
                      '';
                    };

                    luaFn = mkOption {
                      type = types.nullOr types.anything;
                      default = null;
                      description = ''
                        Inline Lua function using lib.mkLuaInline.
                        Use for complex logic that needs multiple statements.
                        Mutually exclusive with cmd, lua, and raw.

                        Example: luaFn = lib.mkLuaInline "function() ... end";
                      '';
                    };

                    raw = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = ''
                        Raw action string (passed through unchanged).
                        Use when you need direct control over the action format.
                        Mutually exclusive with cmd, lua, and luaFn.
                      '';
                    };

                    mode = mkOption {
                      type = types.nullOr (types.listOf types.str);
                      default = null;
                      description = "Modes (overrides group default)";
                    };

                    silent = mkOption {
                      type = types.nullOr types.bool;
                      default = null;
                    };
                  };
                }) (binding: let
                  actionTypes = [binding.cmd binding.lua binding.luaFn binding.raw];
                  nonNullCount = lib.length (lib.filter (x: x != null) actionTypes);
                in
                  if nonNullCount == 1
                  then true
                  else throw "Keybinding must specify exactly one action type (cmd, lua, luaFn, or raw). Currently specified: ${toString nonNullCount}"));
              default = {};
              description = "Direct keybindings at this level";
            };

            groups = mkOption {
              type = types.attrsOf keybindingNodeType;
              default = {};
              description = "Nested subgroups";
            };
          };
        };

        # Helper functions

        processAction = binding:
          if binding.cmd != null
          then binding.cmd
          else if binding.lua != null
          then "function() ${binding.lua} end"
          else if binding.luaFn != null
          then
            if builtins.isAttrs binding.luaFn && binding.luaFn ? expr
            then binding.luaFn.expr # Extract from lib.mkLuaInline
            else binding.luaFn # Use as-is if already a string
          else binding.raw; # Assertions guarantee exactly one action type is set

        flattenKeybindings = prefix: node: let
          nodeDefaults = node.defaults or {};
          directKeys =
            lib.mapAttrsToList (key: binding: {
              key = "${prefix}${key}";
              inherit (binding) desc;
              mode =
                if binding.mode != null
                then binding.mode
                else if nodeDefaults.mode != null
                then nodeDefaults.mode
                else ["n"];
              silent =
                if binding.silent != null
                then binding.silent
                else if nodeDefaults.silent != null
                then nodeDefaults.silent
                else true;
              lua =
                # Determine if this is a Lua action based on action type
                if binding.lua != null || binding.luaFn != null
                then true
                else false;
              action = processAction binding;
            })
            node.keys or {};
          groupKeys = lib.flatten (lib.mapAttrsToList (
              groupKey: groupNode:
                flattenKeybindings "${prefix}${groupKey}" groupNode
            )
            node.groups or {});
        in
          directKeys ++ groupKeys;

        extractWhichKeyGroups = prefix: node: let
          currentGroups =
            lib.mapAttrsToList (
              groupKey: groupNode: let
                fullPrefix = "${prefix}${groupKey}";
              in
                lib.optionalAttrs (groupNode.desc != null) {
                  "${fullPrefix}" = groupNode.desc;
                }
            )
            node.groups or {};
          subGroups = lib.flatten (lib.mapAttrsToList (
              groupKey: groupNode:
                extractWhichKeyGroups "${prefix}${groupKey}" groupNode
            )
            node.groups or {});
        in
          lib.mergeAttrsList (currentGroups ++ subGroups);
      in {
        options.vim.keybindingTree = mkOption {
          type = keybindingNodeType;
          default = {
            keys = {};
            groups = {};
          };
          description = "Tree-structured keybinding configuration";
        };

        config = mkIf (config.vim.keybindingTree
          != {
            keys = {};
            groups = {};
          }) {
          vim.keymaps = flattenKeybindings "" config.vim.keybindingTree;
          vim.binds.whichKey = {
            enable = true;
            register = extractWhichKeyGroups "" config.vim.keybindingTree;
          };
        };
      })

      # Consumer module with actual keybindings
      {
        config.vim = {
          # Use the new keybinding tree system
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
            -- local smart_split = require('smart-splits')
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
