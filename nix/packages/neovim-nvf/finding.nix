{
  vim = {
    # So we don't have to `require('snacks')` all over the damn place
    luaConfigPre = ''
      local snacks = require('snacks')
    '';

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

    keybindingTree = {
      groups = {
        "<leader>" = {
          keys = {
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
                  desc = "Find files";
                  lua = "snacks.picker.smart()";
                };
                "h" = {
                  desc = "Find hidden files";
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
                  desc = "Find help tags";
                  lua = "snacks.picker.help()";
                };
                "b" = {
                  desc = "Find buffers";
                  lua = "snacks.picker.buffers()";
                };
                "g" = {
                  desc = "Find grep content";
                  lua = "snacks.picker.grep()";
                };
                "m" = {
                  desc = "Find marks";
                  lua = "snacks.picker.marks()";
                };
                "r" = {
                  desc = "Find recent files";
                  lua = "snacks.picker.recent()";
                };
                "c" = {
                  desc = "Find recent commands";
                  lua = "snacks.picker.command_history()";
                };
                "d" = {
                  desc = "Find buffer diagnostics";
                  lua = "snacks.picker.diagnostics_buffer()";
                };
                "D" = {
                  desc = "Find all diagnostics";
                  lua = "snacks.picker.diagnostics()";
                };
                "u" = {
                  desc = "Find undo history";
                  lua = "snacks.picker.undo()";
                };
                "R" = {
                  desc = "Find registers";
                  lua = "snacks.picker.registers()";
                };
                "p" = {
                  desc = "Find pickers";
                  lua = "snacks.picker.pickers()";
                };
                "n" = {
                  desc = "Find notifications";
                  lua = "snacks.picker.notifications()";
                };
                "F" = {
                  desc = "Smart Finder";
                  lua = "snacks.picker.smart()";
                };
                "L" = {
                  desc = "Resume last search";
                  lua = "snacks.picker.resume()";
                };
              };
            };
          };
        };
      };
    };
  };
}
