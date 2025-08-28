{
  config.vim = {
    git = {
      neogit.enable = true;
      gitsigns.enable = true;
      gitlinker-nvim.enable = true;
    };

    keybindingTree = {
      groups = {
        "<leader>" = {
          groups = {
            "g" = {
              desc = "Git";
              keys = {
                "g" = {
                  desc = "Open Neogit UI";
                  cmd = "<cmd>Neogit<cr>";
                };
                "b" = {
                  desc = "Blame Current Line";
                  lua = "snacks.git.blame_line()";
                };
                "n" = {
                  desc = "Go to next hunk";
                  lua = "require('gitsigns.actions').next_hunk()";
                };
                "p" = {
                  desc = "Go to previous hunk";
                  lua = "require('gitsigns.actions').prev_hunk()";
                };
                "x" = {
                  desc = "Reset hunk";
                  lua = "require('gitsigns').reset_hunk()";
                };
                "s" = {
                  desc = "Stage hunk";
                  lua = "require('gitsigns').stage_hunk()";
                };
                "u" = {
                  desc = "Unstage hunk";
                  lua = "require('gitsigns').undo_stage_hunk()";
                };
                "o" = {
                  desc = "Open current file in browser";
                  lua = "snacks.gitbrowse()";
                };
                "y" = {
                  desc = "Copy permalink to clipboard";
                  lua = ''
                    require('gitlinker').link({
                      action = function(url)
                        vim.fn.setreg('"', url)
                      end,
                      lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
                      lend = vim.api.nvim_buf_get_mark(0, '>')[1],
                    })
                  '';
                };
              };
            };

            "fG" = {
              desc = "Find Git";
              keys = {
                "b" = {
                  desc = "Find Git branches";
                  lua = "snacks.picker.git_branches()";
                };
                "l" = {
                  desc = "Find Git log";
                  lua = "snacks.picker.git_log()";
                };
                "L" = {
                  desc = "Find Git log line";
                  lua = "snacks.picker.git_log_line()";
                };
                "s" = {
                  desc = "Find Git status";
                  lua = "snacks.picker.git_status()";
                };
                "S" = {
                  desc = "Find Git stash";
                  lua = "snacks.picker.git_stash()";
                };
                "d" = {
                  desc = "Find Git diff (hunks)";
                  lua = "snacks.picker.git_diff()";
                };
                "f" = {
                  desc = "Find Git log files";
                  lua = "snacks.picker.git_log_file()";
                };
              };
            };
          };
        };
      };
    };
  };
}
