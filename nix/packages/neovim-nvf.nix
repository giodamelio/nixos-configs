{
  inputs,
  pkgs,
  ...
}: let
  inherit (pkgs) lib;
  std = inputs.nix-std.lib;
  inherit (std.tuple) tuple3;
  # inherit (lib.nvim.binds) mkKeymap mkLuaBinding;
  inherit (inputs.nvf.lib.nvim.lua) toLuaObject;
  # pretty = val: lib.trace (lib.generators.toPretty {multiline = true;} val) val;
in
  (inputs.nvf.lib.neovimConfiguration {
    inherit pkgs;

    modules = [
      {
        config.vim = {
          lsp.enable = true;

          theme = {
            enable = true;
            name = "tokyonight";
            style = "moon";
          };

          luaConfigPre = ''
            local snacks = require('snacks')
            local smart_split = require('smart-splits')
          '';

          keymaps = let
            # Wrap Lua Function
            lf = func: lib.mkLuaInline "function() ${func} end";

            # Command helper
            cmd = command: "<cmd>${command}<cr>";

            # Require helper
            req = module: func: lf "require('${module}').${func}";

            # Convert a tuple to an attrset based on a list of key names
            tupleToAttrset = keysList: tuple: let
              mapToKv = index: key: {"${key}" = lib.attrsets.getAttr "_${builtins.toString index}" tuple;};
              listOfAttrs = lib.lists.imap0 mapToKv keysList;
            in
              lib.attrsets.mergeAttrsList listOfAttrs;

            # Help in making a whole group of similar bindings
            mkLeaderGroup = keyPrefix: functionPrefix: bindings:
              bindings
              |> lib.lists.map (tuple: (tupleToAttrset ["key" "desc" "action"] tuple))
              |> lib.lists.map (keyBinding:
                keyBinding
                // {
                  key = "${keyPrefix}${keyBinding.key}";
                  # Add the prefix if we have a string, otherwise pass it through
                  action =
                    if builtins.typeOf keyBinding.action == "string"
                    then "${functionPrefix}.${keyBinding.action}"
                    else toLuaObject keyBinding.action;
                  mode = ["n"];
                  lua = true;
                  silent = true;
                });
          in
            (mkLeaderGroup "<leader>f" "snacks.picker" [
              (tuple3 "f" "By file name" "smart")
              (tuple3 "h" "By file name (including hidden)"
                (lib.mkLuaInline ''
                  function()
                    snacks.picker.files({
                      finder = 'files',
                      format = 'file',
                      show_empty = true,
                      hidden = true,
                      ignored = true,
                      follow = false,
                      supports_live = true,
                    })
                  end
                ''))
              (tuple3 "?" "By help tag" "help")
              (tuple3 "b" "By buffer name" "buffers")
              (tuple3 "g" "By file content" "grep")
              (tuple3 "m" "By mark" "marks")
              (tuple3 "r" "By recent files" "recent")
              (tuple3 "c" "By cmd history" "command_history")
              (tuple3 "d" "By buffer diagnostic" "diagnostics_buffer")
              (tuple3 "D" "By project diagnostic" "diagnostics")
              (tuple3 "u" "By undo history" "undo")
              (tuple3 "r" "By history" "registers")
              (tuple3 "p" "By picker" "pickers")
              (tuple3 "n" "By notifications" "notifications")
              # TODO: enable this if we ever switch to using lazy plugin loader
              # (tuple3 "l" "By plugin spec" "lazy")
              (tuple3 "r" "Resume last" "resume")
            ])
            ++ (mkLeaderGroup "<leader>fG" "snacks.picker" [
              (tuple3 "b" "Git branches" "git_branches")
              (tuple3 "l" "Git log" "git_log")
              (tuple3 "L" "Git log line" "git_log_line")
              (tuple3 "s" "Git status" "git_status")
              (tuple3 "S" "Git stash" "git_stash")
              (tuple3 "d" "Git diff (hunks)" "git_diff")
              (tuple3 "f" "Git log files" "git_log_file")
            ])
            ++ (mkLeaderGroup "<leader>d" "" [
              (tuple3 "d" "Trouble document diagnostics" (cmd "TroubleToggle document_diagnostics"))
              (tuple3 "e" "Trouble LSP definitions" (cmd "TroubleToggle lsp_definitions"))
              (tuple3 "i" "Trouble LSP implementations" (cmd "TroubleToggle lsp_implementations"))
              (tuple3 "r" "Trouble LSP references" (cmd "TroubleToggle lsp_references"))
              (tuple3 "n" "Next Diagnostic" (lf "vim.diagnostic.jump({ count = 1 })"))
              (tuple3 "p" "Prev Diagnostic" (lf "vim.diagnostic.jump({ count = -1 })"))
              (tuple3 "t" "Toggle Trouble" (cmd "TroubleToggle"))
            ])
            ++ (mkLeaderGroup "<leader>t" "" [
              (tuple3 "f" "Run tests in file" (req "neotest" "run.run(vim.fn.expand('%'))"))
              (tuple3 "p" "Toggle output panel" (req "neotest" "output_panel.toggle()"))
              (tuple3 "s" "Toggle summary" (req "neotest" "summary.toggle()"))
              (tuple3 "t" "Run nearest test" (req "neotest" "run.run()"))
              (tuple3 "w" "Watch tests in file" (req "neotest" "watch.toggle(vim.fn.expand('%'))"))
              (tuple3 "a" "Attach to running test" (req "neotest" "run.attach()"))
              (tuple3 "l" "Run last test" (req "neotest" "run.run_last()"))
            ])
            ++ (mkLeaderGroup "<leader>l" "" [
              (tuple3 "D" "Show definitions" "snacks.picker.lsp_definitions")
              (tuple3 "d" "Show declarations" "snacks.picker.lsp_declarations")
              (tuple3 "i" "Show implementations" "snacks.picker.lsp_implementations")
              (tuple3 "l" "Show code actions" (lf "vim.lsp.buf.code_action"))
              (tuple3 "s" "Show buffer symbols" "snacks.picker.lsp_symbols")
              (tuple3 "S" "Show workspace symbols" "snacks.picker.workspace_lsp_symbols")
              (tuple3 "r" "Show references" "snacks.picker.lsp_references")
              (tuple3 "t" "Show type definition" "snacks.picker.lsp_type_definitions")
              (tuple3 "f" "Format buffer" (lf "vim.lsp.buf.format"))
            ])
            ++ (mkLeaderGroup "<leader>o" "" [
              (tuple3 "c" "Clear the internal reference to other file" (cmd "OtherClear"))
              (tuple3 "o" "Open the other file" (cmd "Other"))
              (tuple3 "s" "Open the other file in a horizontal split" (cmd "OtherSplit"))
              (tuple3 "v" "Open the other file in a vertical split" (cmd "OtherVSplit"))
            ])
            ++ (mkLeaderGroup "<leader>c" "" [
              (tuple3 "c" "Toggle Claude" (cmd "ClaudeCode"))
              (tuple3 "f" "Focus Claude" (cmd "ClaudeCodeFocus"))
              (tuple3 "r" "Resume Claude" (cmd "ClaudeCode --resume"))
              (tuple3 "C" "Continue Claude" (cmd "ClaudeCode --continue"))
              (tuple3 "m" "Select Claude model" (cmd "ClaudeCodeSelectModel"))
              (tuple3 "b" "Add current buffer" (cmd "ClaudeCodeAdd %"))
              (tuple3 "a" "Accept diff" (cmd "ClaudeCodeDiffAccept"))
              (tuple3 "d" "Deny diff" (cmd "ClaudeCodeDiffDeny"))
            ])
            ++ (mkLeaderGroup "<leader>g" "" [
              (tuple3 "g" "Open Neogit UI" (cmd "Neogit"))
              (tuple3 "b" "Blame Current Line" (lf "snacks.git.blame_line()"))
              (tuple3 "n" "Go to next hunk" (req "gitsigns.actions" "next_hunk()"))
              (tuple3 "p" "Go to previous hunk" (req "gitsigns.actions" "prev_hunk()"))
              (tuple3 "r" "Reset hunk" (req "gitsigns" "reset_hunk()"))
              (tuple3 "s" "Stage hunk" (req "gitsigns" "stage_hunk()"))
              (tuple3 "u" "Unstage hunk" (req "gitsigns" "undo_stage_hunk()"))
              (tuple3 "o" "Open current file in browser" (lf "snacks.gitbrowse()"))
              (tuple3 "y" "Copy permalink to clipboard" (lf ''
                local gl = require('gitlinker')
                gl.link({
                  action = function(url)
                    vim.fn.setreg('"', url)
                  end,
                  lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
                  lend = vim.api.nvim_buf_get_mark(0, '>')[1],
                })
              ''))
            ])
            ++ [
              # Git visual mode bindings
              {
                key = "<leader>gr";
                desc = "Reset hunk (visual)";
                mode = ["v"];
                lua = true;
                silent = true;
                action = lf ''
                  local gs = require('gitsigns')
                  gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
                '';
              }
              {
                key = "<leader>gs";
                desc = "Stage hunk (visual)";
                mode = ["v"];
                lua = true;
                silent = true;
                action = lf ''
                  local gs = require('gitsigns')
                  gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
                '';
              }
              {
                key = "<leader>gy";
                desc = "Copy permalink to clipboard (visual)";
                mode = ["v"];
                lua = true;
                silent = true;
                action = lf ''
                  local gl = require('gitlinker')
                  gl.link({
                    action = function(url)
                      vim.fn.setreg('"', url)
                    end,
                    lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
                    lend = vim.api.nvim_buf_get_mark(0, '>')[1],
                  })
                '';
              }
            ]
            ++ [
              # Claude Code send in visual mode
              {
                key = "<leader>cs";
                desc = "Send to Claude";
                mode = ["v"];
                action = cmd "ClaudeCodeSend";
              }
            ]
            ++ [
              # LSP hover docs binding
              {
                key = "K";
                desc = "Show hover docs";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "vim.lsp.buf.hover";
              }
            ]
            ++ [
              # Smart Splits - Window resizing (Alt + hjkl)
              {
                key = "<A-h>";
                desc = "Resize window left";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.resize_left";
              }
              {
                key = "<A-j>";
                desc = "Resize window down";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.resize_down";
              }
              {
                key = "<A-k>";
                desc = "Resize window up";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.resize_up";
              }
              {
                key = "<A-l>";
                desc = "Resize window right";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.resize_right";
              }
              # Smart Splits - Moving between splits (Ctrl + hjkl)
              {
                key = "<C-h>";
                desc = "Move cursor left";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_left";
              }
              {
                key = "<C-j>";
                desc = "Move cursor down";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_down";
              }
              {
                key = "<C-k>";
                desc = "Move cursor up";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_up";
              }
              {
                key = "<C-l>";
                desc = "Move cursor right";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_right";
              }
              {
                key = "<C-\\>";
                desc = "Move to previous split";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_previous";
              }
              # Smart Splits - Terminal mode navigation
              {
                key = "<C-h>";
                desc = "Move cursor left (terminal)";
                mode = ["t"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_left";
              }
              {
                key = "<C-j>";
                desc = "Move cursor down (terminal)";
                mode = ["t"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_down";
              }
              {
                key = "<C-k>";
                desc = "Move cursor up (terminal)";
                mode = ["t"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_up";
              }
              {
                key = "<C-l>";
                desc = "Move cursor right (terminal)";
                mode = ["t"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_right";
              }
              # Smart Splits - Visual mode navigation
              {
                key = "<C-h>";
                desc = "Move cursor left (visual)";
                mode = ["v"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_left";
              }
              {
                key = "<C-j>";
                desc = "Move cursor down (visual)";
                mode = ["v"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_down";
              }
              {
                key = "<C-k>";
                desc = "Move cursor up (visual)";
                mode = ["v"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_up";
              }
              {
                key = "<C-l>";
                desc = "Move cursor right (visual)";
                mode = ["v"];
                lua = true;
                silent = true;
                action = "smart_split.move_cursor_right";
              }
            ]
            ++ (mkLeaderGroup "<leader><leader>" "" [
              (tuple3 "h" "Swap buffer left" (lf "smart_split.swap_buf_left()"))
              (tuple3 "j" "Swap buffer down" (lf "smart_split.swap_buf_down()"))
              (tuple3 "k" "Swap buffer up" (lf "smart_split.swap_buf_up()"))
              (tuple3 "l" "Swap buffer right" (lf "smart_split.swap_buf_right()"))
            ])
            ++ [
              # Local leader bindings
              {
                key = "<localleader>f";
                desc = "Format current file with treefmt";
                mode = ["n"];
                action = cmd "Treefmt";
              }
            ]
            ++ [
              # Basic utility bindings
              {
                key = "<leader><Tab>";
                desc = "Switch to last buffer";
                mode = ["n"];
                action = cmd "edit #";
              }
              {
                key = "<leader>/";
                desc = "Toggle terminal";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "snacks.terminal.toggle";
              }
              {
                key = "<leader>/";
                desc = "Toggle terminal";
                mode = ["t"];
                lua = true;
                silent = true;
                action = "snacks.terminal.toggle";
              }
              {
                key = "<leader>`";
                desc = "Open explorer";
                mode = ["n"];
                lua = true;
                silent = true;
                action = "snacks.explorer.open";
              }
            ];

          # ++ [
          #   {
          #     key = "<leader>ff";
          #     desc = "Find file";
          #     mode = ["n"];
          #     lua = true;
          #     silent = true;
          #     action = "snacks.picker.smart";
          #   }
          # ];

          binds = {
            whichKey = {
              enable = true;
              register = {
                "<leader>l" = "LSP";
                "<leader>f" = "Fuzzy find";
                "<leader>fG" = "Git";
                "<leader>d" = "Diagnostics/Trouble";
                "<leader>t" = "Testing";
                "<leader>o" = "Other files";
                "<leader>c" = "Claude Code";
                "<leader>g" = "Git";
              };
            };
          };

          languages = {
            nix.enable = true;
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
