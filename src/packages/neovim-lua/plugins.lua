-- Trouble
require('trouble').setup()

-- Telescope
local telescope = require('telescope')
local trouble = require('trouble.providers.telescope')

-- Allow opening telescope results in Trouble
telescope.setup({
  defaults = {
    mappings = {
      i = { ['<c-t>'] = trouble.open_with_trouble },
      n = { ['<c-t>'] = trouble.open_with_trouble },
    },
  },
})

-- Snippets
require('luasnip.loaders.from_vscode').lazy_load()

-- Status bar
local lualine = require('lualine')
local default_config = lualine.get_config()

-- Enable lualine
local config = vim.tbl_deep_extend('force', default_config, {
  sections = {
    lualine_c = { 'filename', 'lsp_progress' },
  },
  winbar = {
    lualine_c = {
      {
        'navic',
        color_correction = nil,
        navic_opts = nil,
      },
    },
  },
  -- Show some help when the tabline is open, I always forget the keys...
  tabline = {
    lualine_a = { { 'tabs', mode = 2 } },
    lualine_x = { '"[next tab] gt, [prev tab] gT, [close tab] :tabclose"' },
  },
})
lualine.setup(config)

-- Hide mode display in the command bar since lualine shows it
vim.opt.showmode = false

-- Only show the tabline if there is more then one tab
vim.opt.showtabline = 1

-- Git Status in Gutter
local gs = require('gitsigns')
local gsa = require('gitsigns.actions')
local gl = require('gitlinker')
local gla = require('gitlinker.actions')
local neogit = require('neogit')

gs.setup({
  current_line_blame = true,
})

gl.setup({
  mapping = nil,
})

neogit.setup()

-- ChatGPT
require('chatgpt').setup({
  yank_register = 'C',
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
})

-- Oil
require('oil').setup({
  columns = { 'icon', 'permissions', 'size' },
})

require('nvim-surround').setup()
require('Comment').setup()
require('stay-centered').setup()
