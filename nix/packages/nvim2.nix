{perSystem, ...}: let
  rawLua = lua: {
    __raw = lua;
  };
in
  perSystem.nixvim.makeNixvim {
    colorschemes.tokyonight = {
      enable = true;
    };

    globals = {
      mapleader = " ";
      maplocalleader = ",";
    };

    opts = {
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

      # Hide mode display in the command bar since lualine shows it
      showmode = false;

      # Only show the tabline if there is more then one tab
      showtabline = 1;
    };

    lsp = {
      servers = {
        lua_ls.enable = true;
      };
    };

    plugins = {
      # Incremental parser for highliting
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };
      rainbow-delimiters = {
        enable = true;
        highlight = [
          "RainbowDelimiterRed"
          "RainbowDelimiterYellow"
          "RainbowDelimiterBlue"
          "RainbowDelimiterOrange"
          "RainbowDelimiterGreen"
          "RainbowDelimiterViolet"
          "RainbowDelimiterCyan"
        ];
      };

      # Language Servers
      lspconfig.enable = true;

      which-key = {
        enable = true;
        settings = {
          spec = let
            mkGroup = title: key: {
              __unkeyed-1 = "<leader>${key}";
              group = title;
            };
          in [
            (mkGroup "Find" "f")
            (mkGroup "Commands" "fc")
            (mkGroup "Diagnostics/Trouble" "d")
            (mkGroup "Testing" "t")
            (mkGroup "LSP" "l")
            (mkGroup "Other files" "o")
            (mkGroup "Git" "g")
          ];
        };
      };
      web-devicons.enable = true;
      telescope = {
        enable = true;
        settings = {
          defaults = {
            mappings = {
              i = {"<c-t>" = rawLua "require('trouble.sources.telescope').open";};
              n = {"<c-t>" = rawLua "require('trouble.sources.telescope').open";};
            };
          };
        };
      };
      trouble = {
        enable = true;
      };

      # Completion
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          sources = [
            {name = "nvim_lsp";}
            {name = "path";}
            {name = "buffer";}
            {name = "cmdline";}
            {name = "luasnip";}
            {name = "git";}
          ];
          snippet.expand = ''
            function(args)
              require('luasnip').lsp_expand(args.body)
            end
          '';
          mapping = rawLua ''
            cmp.mapping.preset.insert({
              ['<C-b>'] = cmp.mapping.scroll_docs(-4),
              ['<C-f>'] = cmp.mapping.scroll_docs(4),
              ['<C-Space>'] = cmp.mapping.complete(),
              ['<C-e>'] = cmp.mapping.abort(),
              ['<CR>'] = cmp.mapping.confirm({ select = true }),
              ['<Tab>'] = cmp.mapping(function(fallback)
                local luasnip = require('luasnip')

                local has_words_before = function()
                  -- luacheck: ignore
                  unpack = unpack or table.unpack
                  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
                  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match('%s') == nil
                end

                if cmp.visible() then
                  cmp.select_next_item()
                elseif luasnip.expand_or_locally_jumpable() then
                  luasnip.expand_or_jump()
                elseif has_words_before() then
                  cmp.complete()
                else
                  fallback()
                end
              end),
              ['<S-Tab>'] = cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_prev_item()
                elseif luasnip.jumpable(-1) then
                  luasnip.jump(-1)
                else
                  fallback()
                end
              end),
            })
          '';
          window = {
            completion = rawLua "cmp.config.window.bordered()";
            documentation = rawLua "cmp.config.window.bordered()";
          };
        };
      };

      # Snippets
      luasnip = {
        enable = true;
        fromVscode = [{}];
      };
      friendly-snippets.enable = true;

      # Status Bar
      lualine = {
        enable = true;
        settings = {
          sections = {
            lualine_c = ["filename" "lsp_progress"];
          };
          winbar = {
            lualine_c = [
              {
                __unkeyed-1 = "navic";
                color_correction = null;
                navic_opts = null;
              }
            ];
          };
          tabline = {
            lualine_a = [
              {
                __unkeyed-1 = "tabs";
                mode = 2;
              }
            ];
            lualine_x = [{__unkeyed-1 = ''"[next tab] gt, [prev tab] gT, [close tab] :tabclose"'';}];
          };
        };
      };
      navic.enable = true;

      # Show Git status in the gutter
      gitsigns = {
        enable = true;
        settings = {
          current_line_blame = true;
        };
      };

      # Allow copying Github links to files to the clipboard
      gitlinker = {
        enable = true;
      };

      # Git TUI
      neogit.enable = true;

      # Move/Create/Delete files/directories directly in a vim buffer
      oil = {
        enable = true;
        settings = {
          columns = ["icon" "permissions" "size"];
        };
      };

      # Inline Test Running
      neotest = {
        enable = true;
        adapters = {
          rust.enable = true;
          elixir.enable = true;
          go.enable = true;
          deno.enable = true;
          rspec.enable = true;
        };
      };
    };

    keymaps = let
      mkRequireFunBinding = require: binding: function: description: {
        key = binding;
        action = rawLua "require('${require}').${function}";
        options.desc = description;
      };
      mkTelescopeBinding = mkRequireFunBinding "telescope.builtin";
      mkGitsignsBinding = mkRequireFunBinding "gitsigns";
      mkGitsignsActionsBinding = mkRequireFunBinding "gitsigns.actions";
    in [
      # Misc top level bindings
      {
        key = "<leader><Tab>";
        action = "<cmd>edit #<cr>";
      }

      # Fuzzy finding
      (mkTelescopeBinding "<leader>f?" "help_tags" "Find help tags")
      (mkTelescopeBinding "<leader>ff" "find_files" "Find file")
      (mkTelescopeBinding "<leader>fb" "buffers" "Find buffer")
      (mkTelescopeBinding "<leader>fg" "live_grep" "Find line in file")
      (mkTelescopeBinding "<leader>fm" "marks" "Find marks")
      (mkTelescopeBinding "<leader>fr" "oldfiles" "Find recent files")
      (mkTelescopeBinding "<leader>fs" "search_history" "Find search history")
      (mkTelescopeBinding "<leader>fcc" "commands" "Find commands")
      (mkTelescopeBinding "<leader>fch" "command_history" "Find command history")
      {
        key = "<leader>fh";
        action = rawLua ''
          function()
            require('telescope.builtin').find_files({ hidden = true })
          end
        '';
        options.desc = "Find file (including hidden)";
      }

      # Diagnostics and Trouble.nvim
      {
        key = "<leader>dd";
        action = "<cmd>TroubleToggle document_diagnostics<cr>";
        options.desc = "Trouble document diagnostics";
      }

      # Git
      {
        key = "<leader>gg";
        action = "<cmd>Neogit<cr>";
        options.desc = "Open Neogit";
      }
      {
        key = "<leader>gb";
        action = rawLua ''
          function()
            require('gitsigns').blame_line(true)
          end
        '';
        options.desc = "Blame Current Line";
      }
      {
        key = "<leader>gy";
        action = "<cmd>GitLink<cr>";
        options.desc = "Copy Github Permalink";
      }
      (mkGitsignsActionsBinding "<leader>gn" "next_hunk" "Go to next hunk")
      (mkGitsignsActionsBinding "<leader>gp" "prev_hunk" "Go to previous hunk")
      (mkGitsignsBinding "<leader>gr" "reset_hunk" "Reset hunk")
      (mkGitsignsBinding "<leader>gs" "stage_hunk" "Stage hunk")
      (mkGitsignsBinding "<leader>gu" "undo_stage_hunk" "Unstage hunk")
    ];
  }
