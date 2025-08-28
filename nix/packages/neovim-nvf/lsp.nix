{
  vim = {
    lsp = {
      enable = true;
      lightbulb.enable = true; # Show lightbulb for code actions
      lspkind.enable = true; # Show the type of a completion item with an emoji
      lspsaga.enable = true; # Improve LSP experience
      trouble = {
        enable = true;
        mappings = {
          locList = null;
          quickfix = "<leader>dq";
          symbols = "<leader>ds";
        };
      };

      mappings = {
        format = "<leader>lF";
      };
    };

    keybindingTree = {
      keys = {
        "K" = {
          desc = "Show hover docs";
          cmd = "<cmd>Lspsaga hover_doc<cr>";
        };
      };

      groups = {
        "<leader>" = {
          groups = {
            "l" = {
              desc = "LSP";
              groups.g.desc = "Go to";
              groups.t.desc = "Toggle";
              groups.w.desc = "Workspace";

              keys = {
                "f" = {
                  desc = "Finder";
                  cmd = "<cmd>Lspsaga finder<cr>";
                };
                "n" = {
                  desc = "Rename symbol";
                  cmd = "<cmd>Lspsaga rename";
                };
              };
            };

            "d" = {
              desc = "Trouble/Diagnostics";
              keys = {
                "d" = {
                  desc = "Trouble buffer diagnostics";
                  cmd = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
                };
                "n" = {
                  desc = "Go to next diagnostic";
                  cmd = "<cmd>Lspsaga diagnostic_jump_next<cr>";
                };
                "p" = {
                  desc = "Go to prev diagnostic";
                  cmd = "<cmd>Lspsaga diagnostic_jump_prev<cr>";
                };
              };
            };
          };
        };
      };
    };
  };
}
