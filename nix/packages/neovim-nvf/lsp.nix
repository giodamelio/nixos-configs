{
  vim = {
    lsp = {
      enable = true;
      lightbulb.enable = true; # Show lightbulb for code actions
      lspkind.enable = true; # Show the type of a completion item with an emoji
      lspsaga.enable = true; # Improve LSP experience
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
            };
          };
        };
      };
    };
  };
}
