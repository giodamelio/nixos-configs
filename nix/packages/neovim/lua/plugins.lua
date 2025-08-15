-- Trouble
require('trouble').setup()

-- Telescope
local telescope = require('telescope')
local trouble = require('trouble.sources.telescope')

-- Allow opening telescope results in Trouble
telescope.setup({
  defaults = {
    mappings = {
      i = { ['<c-t>'] = trouble.open },
      n = { ['<c-t>'] = trouble.open },
    },
  },
})

-- Snippets
require('luasnip.loaders.from_vscode').lazy_load()

-- Status bar
local lualine = require('lualine')
local default_config = lualine.get_config()

-- Get the current session name
-- local function get_session_name()
--   local current_session_path = vim.api.nvim_get_vvar('this_session')
--   if current_session_path ~= "" then
--     local session_name = vim.fn.fnamemodify(current_session_path, ':t')
--     -- Remove file extension if present
--     session_name = session_name:gsub("%.vim$", "")
--     return "📁 " .. session_name
--   end
--   return ""
-- end

-- Enable lualine
local config = vim.tbl_deep_extend('force', default_config, {
  sections = {
    lualine_c = { 'filename', 'lsp_progress' },
    -- TODO: make this actually work at somepoint
    -- lualine_y = {
    --   get_session_name,
    -- },
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
local gl = require('gitlinker')
local neogit = require('neogit')

gs.setup({
  current_line_blame = true,
})

gl.setup({
  mapping = nil,
})

neogit.setup()

-- Avante
require('avante_lib').load()
require('avante').setup()

-- Oil
require('oil').setup({
  columns = { 'icon', 'permissions', 'size' },
})

-- Open Oil if no file/directory is specified
-- vim.api.nvim_create_autocmd('VimEnter', {
--   callback = function()
--     if vim.fn.argc() == 0 then vim.defer_fn(function() require('oil').open() end, 10) end
--   end,
-- })

-- NeoTest
require('neotest').setup({
  adapters = {
    require('neotest-rust'),
    require('neotest-elixir'),
    require('neotest-go'),
    require('neotest-deno'),
    require('neotest-rspec'),
  },
})

-- Elixir Tools
require('elixir').setup({
  nextls = {
    enable = true,
    cmd = os.getenv('NEXTLS_CMD'),
    init_options = {
      experimental = {
        completions = {
          enable = true,
        },
      },
    },
  },
  elixirls = { enable = false },
  projectionist = { enable = true },
})

-- Other
require('other-nvim').setup({
  mappings = {
    'rails',
    'golang',
    -- Elixir + Phoenix Mappings

    -- Go from controller to places
    {
      pattern = '/lib/(.+)_web/controllers/(.+)_controller.ex',
      target = {
        { context = 'test', target = '/test/%1_web/controllers/%2_controller_test.exs' },
      },
    },
    -- Go from controller test to places
    {
      pattern = '/test/(.+)_web/controllers/(.+)_controller_test.exs',
      target = {
        { context = 'controller', target = '/lib/%1_web/controllers/%2_controller.ex' },
      },
    },
    -- Go from context to places
    {
      pattern = '/lib/(.+)/(.+).ex',
      target = {
        { context = 'test', target = '/test/%1/%2_test.exs' },
      },
    },
    -- Go from context test to places
    {
      pattern = '/test/(.+)/(.+)_test.exs',
      target = {
        { context = 'context', target = '/lib/%1/%2.ex' },
      },
    },
  },
})

-- FZF Lua
require('fzf-lua').setup({ 'default' })

-- Parrot
-- require('parrot').setup({
--   providers = {
--     openai = {
--       api_key = os.getenv("OPENAI_API_KEY"),
--     },
--     anthropic = {
--       api_key = os.getenv("ANTHROPIC_API_KEY"),
--     },
--   },
--
--   chat_shortcut_respond = { modes = { 'n', 'i', 'v', 'x' }, shortcut = '<C-Enter>' },
-- })

-- Snacks setup
local snacks = require('snacks')
snacks.setup({
  dashboard = {
    pane_gap = 4,
    preset = {
      keys = {
        { icon = ' ', key = 'f', desc = 'Find File', action = ":lua Snacks.dashboard.pick('files')" },
        { icon = ' ', key = 'n', desc = 'New File', action = ':ene | startinsert' },
        { icon = ' ', key = 'g', desc = 'Find Text', action = ":lua Snacks.dashboard.pick('live_grep')" },
        { icon = ' ', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
        {
          icon = ' ',
          key = 'c',
          desc = 'Config',
          action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.expand('$HOME/nixos-configs/nix/packages/neovim')})",
        },
        { icon = ' ', key = 's', desc = 'Restore Session', section = 'session' },
        { icon = ' ', key = 'q', desc = 'Quit', action = ':qa' },
      },
    },
    sections = {
      { section = 'header' },
      { section = 'keys', gap = 1, padding = 1 },
      { pane = 2, icon = ' ', title = 'Recent Files', section = 'recent_files', indent = 2, padding = 1 },
      -- TODO: enable this if we ever switch over to using the Lazy plugin loader
      -- { pane = 2, title = "Sessions", section = "sessions", indent = 2, padding = 1},
      { pane = 2, icon = ' ', title = 'Projects', section = 'projects', indent = 2, padding = 1 },
      {
        pane = 2,
        icon = ' ',
        title = 'Git Status',
        section = 'terminal',
        enabled = function() return snacks.git.get_root() ~= nil end,
        cmd = 'git status --short --branch --renames',
        height = 5,
        padding = 1,
        ttl = 5 * 60,
        indent = 3,
      },
      -- TODO: Enable this if we ever switch to Lazy plugin loader (which I want to look into)
      -- { section = "startup" },
    },
  },
  picker = {
    config = function(opts)
      -- Add an open in trouble keybinding
      return vim.tbl_deep_extend('force', opts or {}, {
        actions = require('trouble.sources.snacks').actions,
        win = {
          input = {
            keys = {
              ['<C-T>'] = {
                'trouble_open',
                mode = { 'n', 'i' },
              },
            },
          },
        },
      })
    end,
  },
  indent = {
    enable = true,
    animate = {
      enabled = false,
    },
  },
  keys = {
    config = function(opts)
      -- Add an open in trouble keybinding
      return vim.tbl_deep_extend('force', opts or {}, {
        keys = {
          { '<leader>/', function() snacks.terminal() end, desc = 'Toggle Terminal' },
        },
      })
    end,
  },
})

-- Some helper functions for debugging
-- selene: allow(multiple_statements)
_G.dd = function(...) snacks.debug.inspect(...) end
-- selene: allow(multiple_statements)
_G.bt = function() snacks.debug.backtrace() end
vim.print = _G.dd

-- Session management
require('persisted').setup({
  autoload = true,
})

-- Allow searching Persisted sessions with Telescope
telescope.load_extension('persisted')

require('claudecode').setup()
require('nvim-surround').setup()
require('Comment').setup()
require('stay-centered').setup()
require('smart-splits')
