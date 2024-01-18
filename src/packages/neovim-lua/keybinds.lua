local wk = require('which-key')

local telescope = require('telescope')
local tb = require('telescope.builtin')
local trouble = require('trouble.providers.telescope')

wk.register({
  ['<Tab>'] = { '<cmd>edit #<cr>', 'Switch to last buffer' },
}, { prefix = '<leader>' })

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
  t = { '<cmd>TroubleToggle document_diagnostics<cr>', 'Trouble document diagnostics' },
}, { prefix = '<leader>' })

-- Language Server
wk.register({
  K = { vim.lsp.buf.hover, 'Show hover docs' },
  ['<leader>l'] = {
    name = 'LSP',
    l = { vim.lsp.buf.code_action, 'Show code actions' },
    d = { vim.lsp.buf.declaration, 'Show definitions' },
    D = { vim.lsp.buf.definition, 'Show definitions' },
    t = { vim.lsp.buf.type_definition, 'Show type definition' },
    r = { vim.lsp.buf.references, 'Show references' },
    i = { vim.lsp.buf.implementation, 'Show implementations' },
  },
})

-- Git keybindings
local gs = require('gitsigns')
local gsa = require('gitsigns.actions')
local gl = require('gitlinker')
local gla = require('gitlinker.actions')

wk.register({
  g = {
    name = 'Git',
    g = { '<cmd>Neogit<cr>', 'Open Neogit UI' },
    n = { function() gsa.next_hunk() end, 'Go to next hunk' },
    p = { function() gsa.prev_hunk() end, 'Go to previous hunk' },
    s = { function() gs.stage_hunk() end, 'Stage hunk' },
    u = { function() gs.undo_stage_hunk() end, 'Unstage hunk' },
    r = { function() gs.reset_hunk() end, 'Reset hunk' },
    b = { function() gs.blame_line(true) end, 'Blame Current Line' }, -- true shows full blame with a diff
    y = {
      function()
        gl.link({
          -- GitLinker hard codes to the + register which doesn't work over ssh
          -- action = gla.clipboard,
          action = function(url) vim.fn.setreg('"', url) end,
          lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
          lend = vim.api.nvim_buf_get_mark(0, '>')[1],
        })
      end,
      'Copy permalink to clipboard',
    },
  },
}, { prefix = '<leader>' })

-- Some visual mode keybindings
-- TODO: these seem to be broken
wk.register({
  g = {
    name = 'Git',
    s = { function() gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, 'Stage hunk' },
    r = { function() gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, 'Reset hunk' },
    y = {
      function()
        gl.link({
          -- GitLinker hard codes to the + register which doesn't work over ssh
          -- action = gla.clipboard,
          action = function(url) vim.fn.setreg('"', url) end,
          lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
          lend = vim.api.nvim_buf_get_mark(0, '>')[1],
        })
      end,
      'Copy permalink to clipboard',
    },
  },
}, { prefix = '<leader>', mode = 'v' })