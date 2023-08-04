local plugins = {
  -- TokyoNight Colorscheme
  {
    'folke/tokyonight.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('tokyonight').setup({
        style = 'storm',
        styles = {
          -- Don't italazise comments or keywords
          comments = { italic = false },
          keywords = { italic = false }
        }
      })

      vim.cmd [[colorscheme tokyonight]]
    end
  },

  -- Interactivly show keybindings
  {
    'folke/which-key.nvim',
    opts = {},
    config = true,
  },

  -- Fuzzy find all the things
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local wk = require('which-key')
      local builtin = require('telescope.builtin')
      local telescope = require('telescope')
      local tb = require('telescope.builtin');
      --local trouble = require('trouble.providers.telescope')

      wk.register({
        f = {
          name = 'Find',
          f = { function() tb.find_files() end, 'Find file' },
          g = { function() tb.live_grep() end, 'Find line in file' },
          b = { function() tb.buffers() end, 'Find buffer' },
          h = { function() tb.help_tags() end, 'Find buffer' },
          r = { function() tb.oldfiles() end, 'Find recent files' },
          m = { function() tb.marks() end, 'Find marks' },
        },
      }, { prefix = '<leader>' })

      telescope.setup({
        defaults = {
          mappings = {
            --i = { ['<c-t>'] = trouble.open_with_trouble },
            --n = { ['<c-t>'] = trouble.open_with_trouble },
          },
        },
      })

      -- Setup language server bindings
      wk.register({
        l = {
          name = 'LSP',
          l = { function() tb.lsp_code_actions() end, 'Show code actions' },
          r = { function() tb.lsp_references() end, 'Show references' },
          e = { function() tb.lsp_definitions() end, 'Show definitions' },
          t = { function() tb.lsp_type_definitions() end, 'Show type definition' },
          i = { function() tb.lsp_implementations() end, 'Show implementations' },
          s = {
            name = 'Symbols',
            s = { function() tb.lsp_document_symbols() end, 'Show document symbols' },
            w = { function() tb.lsp_workspace_symbols() end, 'Show workspace symbols' },
          },
          d = {
            name = 'Diagnostics',
            d = { function() tb.lsp_document_diagnostics() end, 'Show document diagnostics' },
            w = { function() tb.lsp_workspace_diagnostics() end, 'Show workspace diagnostics' },
          },
        },
      }, { prefix = '<leader>' })
    end
  },

  -- Setup Language Server, Autocomplete and Snippets
  {
    'VonHeikemen/lsp-zero.nvim',
    branch = 'v2.x',
    dependencies = {
      -- LSP Support
      { 'neovim/nvim-lspconfig' }, -- Required

      -- Autocompletion
      { 'hrsh7th/nvim-cmp' },     -- Required
      { 'hrsh7th/cmp-nvim-lsp' }, -- Required
      { 'L3MON4D3/LuaSnip' },     -- Required

      -- Code Context
      { 'SmiteshP/nvim-navic' }
    },
    config = function()
      local lsp = require('lsp-zero').preset({})
      local navic = require('nvim-navic')

      lsp.on_attach(function(client, bufnr)
        lsp.default_keymaps({ buffer = bufnr })
        lsp.buffer_autoformat()

        if client.server_capabilities.documentSymbolProvider then
          navic.attach(client, bufnr)
        end
      end)

      -- Configure the language servers
      local lspconfig = require('lspconfig')

      -- Lua with extra support for Neovim
      lspconfig.lua_ls.setup(lsp.nvim_lua_ls())

      -- Setup with default config
      lsp.setup_servers({
        -- Nix
        'nil_ls',
        -- Rust
        'rust_analyzer'
      })

      -- Setup some additional cmp bindings
      lsp.extend_cmp()
      local cmp = require('cmp')
      cmp.setup({
        mapping = {
          ['<CR>'] = cmp.mapping.confirm()
        }
      })

      lsp.setup()
    end
  },


  -- Treesitter
  {
    'nvim-treesitter/nvim-treesitter',
    config = function()
      local ts = require('nvim-treesitter.configs')

      ts.setup({
        highlight = {
          enable = true,
          disable = {},
        },
        indent = {
          enable = true,
          disable = {},
        },
      })
    end
  },

  -- Rainbow delimiters with Treesitter
  {
    'hiphish/rainbow-delimiters.nvim',
    config = function()
      local rainbow_delimiters = require('rainbow-delimiters')
      local setup = require('rainbow-delimiters.setup')
      setup({
        strategy = {
          [''] = rainbow_delimiters.strategy['global'],
          vim = rainbow_delimiters.strategy['local'],
        },
        query = {
          [''] = 'rainbow-delimiters',
          lua = 'rainbow-blocks',
        },
        highlight = {
          'RainbowDelimiterRed',
          'RainbowDelimiterYellow',
          'RainbowDelimiterBlue',
          'RainbowDelimiterOrange',
          'RainbowDelimiterGreen',
          'RainbowDelimiterViolet',
          'RainbowDelimiterCyan',
        },
      })
    end
  },

  -- Status bar
  {
    'nvim-lualine/lualine.nvim',
    dependencies = {
      { 'kyazdani42/nvim-web-devicons' },
      { 'arkav/lualine-lsp-progress' }
    },
    config = function()
      local lualine = require('lualine')
      local default_config = lualine.get_config()

      -- Enable lualine
      local config = vim.tbl_deep_extend('force', default_config, {
        sections = {
          lualine_c = { 'filename', 'lsp_progress' }
        },
        winbar = {
          lualine_c = {
            {
              'navic',
              color_correction = nil,
              navic_opts = nil
            }
          }
        }
      })
      lualine.setup(config)

      -- Hide mode display in the command bar since lualine shows it
      vim.opt.showmode = false
    end
  },

  -- Lists make your troubles go away!
  {
    'folke/trouble.nvim',
    config = function()
      local trouble = require('trouble')
      local wk = require('which-key')

      trouble.setup()

      -- Setup some keybindings
      wk.register({
        d = {
          name = 'Diagnostics/Trouble',
          t = { '<cmd>TroubleToggle<cr>', 'Time for trouble' },
          d = { '<cmd>TroubleToggle document_diagnostics<cr>', 'Trouble document diagnostics' },
          r = { '<cmd>TroubleToggle lsp_references<cr>', 'Trouble references' },
          e = { '<cmd>TroubleToggle lsp_definitions<cr>', 'Trouble definitions' },
          i = { '<cmd>TroubleToggle lsp_implementations<cr>', 'Trouble implementations' },
          n = { function() vim.diagnostic.goto_next() end, 'Go to next diagnostic' },
          p = { function() vim.diagnostic.goto_prev() end, 'Go to previous diagnostic' },
        },
      }, { prefix = '<leader>' })
    end
  },

  -- Show git status in gutter
  {
    'lewis6991/gitsigns.nvim',
    dependencies = {
      { 'linrongbin16/gitlinker.nvim' }
    },
    config = function()
      local gs = require('gitsigns')
      local gsa = require('gitsigns.actions')
      local gl = require('gitlinker')
      local gla = require('gitlinker.actions')
      local wk = require('which-key')

      gs.setup({
        current_line_blame = true,
      })

      gl.setup({
        mapping = nil
      })

      -- Setup some keybindings
      wk.register({
        g = {
          name = 'Git',
          n = { function() gsa.next_hunk() end, 'Go to next hunk' },
          p = { function() gsa.prev_hunk() end, 'Go to previous hunk' },
          s = { function() gs.stage_hunk() end, 'Stage hunk' },
          u = { function() gs.undo_stage_hunk() end, 'Unstage hunk' },
          r = { function() gs.reset_hunk() end, 'Reset hunk' },
          b = { function() gs.blame_line(true) end, 'Blame Current Line' }, -- true shows full blame with a diff
          y = { function()
            gl.link({
              -- GitLinker hard codes to the + register which doesn't work over ssh
              -- action = gla.clipboard,
              action = function(url)
                vim.fn.setreg('"', url)
              end,
              lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
              lend = vim.api.nvim_buf_get_mark(0, '>')[1]
            })
          end, 'Copy permalink to clipboard' },
        },
      }, { prefix = '<leader>' })

      -- Some visual mode keybindings
      -- TODO: these seem to be broken
      wk.register({
        g = {
          name = 'Git',
          s = { function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, 'Stage hunk' },
          r = { function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, 'Reset hunk' },
          y = { function()
            gl.link({
              -- GitLinker hard codes to the + register which doesn't work over ssh
              -- action = gla.clipboard,
              action = function(url)
                vim.fn.setreg('"', url)
              end,
              lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
              lend = vim.api.nvim_buf_get_mark(0, '>')[1]
            })
          end, 'Copy permalink to clipboard' },
        },
      }, { prefix = '<leader>', mode = 'v' })
    end
  },

  {
    'jackMort/ChatGPT.nvim',
    dependencies = {
      'MunifTanjim/nui.nvim',
    },
    event = 'VeryLazy',
    opts = {
      chat = {
        keymaps = {
          close = { '<Esc>' },
        },
      },
      edit_with_instructions = {
        diff = false,
        keymaps = {
          close = '<Esc>',
        },
      },
      popup_input = {
        submit = 'Enter',
      },
    },
    config = true,
  },

  -- Move/create/delete files directly in a vim buffer
  {
    'stevearc/oil.nvim',
    opts = {
      columns = { 'icon', 'permissions', 'size' }
    },
    config = true,
  },

  -- Better comments
  {
    'numToStr/comment.nvim',
    config = true,
  },

  -- Show marks in the sign
  {
    'chentoast/marks.nvim',
    config = true,
  },

  {
    'arnamak/stay-centered.nvim',
    config = true,
  },

  {
    'NeogitOrg/neogit',
    config = true
  },

  -- Do a Unix to it!
  { 'tpope/vim-eunuch' },

  -- Add a well behaved :Bdelete (keeps splits etc...)
  { 'famiu/bufdelete.nvim' },

  -- Deal with pairs of things
  { 'tpope/vim-surround' },
}

-- Do a crazy dev mode hack if we are useing Nix
-- Basically this sets all the plugins as being in development mode,
-- then uses linkFarm to generate a dir with all the plugins symlinked in the nix store.
-- It also changes the lockfile to be in /tmp, since we don't need it on Nix anyways
if os.getenv('NIX_PATH') then
  -- Add `dev = true` to each plugin
  for _, plugin in ipairs(plugins) do
    plugin.dev = true

    -- Handle the plugin dependencies
    if plugin.dependencies then
      local transformed_deps = {}
      for _, plugin_dep in ipairs(plugin.dependencies) do
        -- If it is a bare string dep, convert it to a table version
        if type(plugin_dep) == "string" then
          table.insert(transformed_deps, {
            plugin_dep,
            dev = true
          })
        else
          plugin_dep.dev = true
          table.insert(transformed_deps, plugin_dep)
        end
      end
      plugin.dependencies = transformed_deps
    end
  end

  return require('lazy').setup(plugins, {
    lockfile = '/tmp/lazy-lock.json',
    dev = {
      path     = "@allThePlugins@",
      fallback = false
    },
  })
else
  return require('lazy').setup(plugins, {})
end
