-- Set the Lazy.nvim lockfile path to a special location if we are on NixOS
local lazy_lockfile_path
if vim.fn.isdirectory(vim.fn.expand('~/nixos-configs')) then
  lazy_lockfile_path = '~/nixos-configs/home/giodamelio/features/neovim/config/lazy-lock.json'
else
  -- Lazy.nvim default
  lazy_lockfile_path = vim.fn.stdpath('config') .. '/lazy-lock.json'
end

return require('lazy').setup({
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
    config = function()
      require('which-key').setup {}
    end
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
      local trouble = require('trouble.providers.telescope')

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
            i = { ['<c-t>'] = trouble.open_with_trouble },
            n = { ['<c-t>'] = trouble.open_with_trouble },
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
    },
    config = function()
      local lsp = require('lsp-zero').preset({})

      lsp.on_attach(function(_client, bufnr)
        lsp.default_keymaps({ buffer = bufnr })
        lsp.buffer_autoformat()
      end)

      -- Configure the language servers
      local lspconfig = require('lspconfig')

      -- Lua with extra support for Neovim
      lspconfig.lua_ls.setup(lsp.nvim_lua_ls())

      -- Nix
      lspconfig.nil_ls.setup({})

      -- Setup some additional cmp bindings
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
    dependencies = {
      { 'p00f/nvim-ts-rainbow' } -- Rainbow parens
    },
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
        rainbow = {
          enable = true,
          disable = {},
        },
      })
    end
  },

  -- Status bar
  {
    'nvim-lualine/lualine.nvim',
    dependencies = {
      { 'kyazdani42/nvim-web-devicons' }
    },
    config = function()
      local lualine = require('lualine')

      -- Enable lualine
      lualine.setup()

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
        },
      }, { prefix = '<leader>' })
    end
  },

  -- Show git status in gutter
  {
    'lewis6991/gitsigns.nvim',
    dependencies = {
      { 'ruifm/gitlinker.nvim' }
    },
    config = function()
      local gs = require('gitsigns')
      local gsa = require('gitsigns.actions')
      local gl = require('gitlinker')
      local wk = require('which-key')

      gs.setup({
        current_line_blame = true,
        keymaps = {}, -- Remove default bindings since we add our own
      })

      gl.setup({
        mappings = nil
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
          y = { function() gl.get_buf_range_url('n') end, 'Get Permalink' },
        },
      }, { prefix = '<leader>' })

      -- Some visual mode keybindings
      -- TODO: these seem to be broken
      wk.register({
        g = {
          name = 'Git',
          s = { function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, 'Stage hunk' },
          r = { function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, 'Reset hunk' },
          y = { function() gl.get_buf_range_url('v') end, 'Get Permalink' },
        },
      }, { prefix = '<leader>', mode = 'v' })
    end
  },

  -- Easy Git
  { 'tpope/vim-fugitive' },

  -- Better comments
  {
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup()
    end,
  },

  -- Language support
  { 'LnL7/vim-nix' } -- Nix
}, {
  lockfile = lazy_lockfile_path
})
