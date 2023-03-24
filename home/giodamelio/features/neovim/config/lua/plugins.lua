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
      wk.register({
          f = {
            name = 'file',
            f = { builtin.find_files, 'Find File' },
            g = { builtin.live_grep, 'Live Grep' }
          },
        },
        { prefix = '<leader>' }
      )
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

  -- Language support
  { 'LnL7/vim-nix' } -- Nix
}, {
  lockfile = lazy_lockfile_path
})
