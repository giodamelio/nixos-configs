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
          '';

          keymaps = let
            # Wrap Lua Function
            lf = func: lib.mkLuaInline "function() ${func} end";

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
              (tuple3 "d" "Trouble document diagnostics" "<cmd>TroubleToggle document_diagnostics<cr>")
              (tuple3 "e" "Trouble LSP definitions" "<cmd>TroubleToggle lsp_definitions<cr>")
              (tuple3 "i" "Trouble LSP implementations" "<cmd>TroubleToggle lsp_implementations<cr>")
              (tuple3 "r" "Trouble LSP references" "<cmd>TroubleToggle lsp_references<cr>")
              (tuple3 "n" "Next Diagnostic" (lf "vim.diagnostic.jump({ count = 1 })"))
              (tuple3 "p" "Prev Diagnostic" (lf "vim.diagnostic.jump({ count = -1 })"))
              (tuple3 "t" "Toggle Trouble" "<cmd>TroubleToggle<cr>")
            ]);

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
        };
      }
    ];
  }).neovim
