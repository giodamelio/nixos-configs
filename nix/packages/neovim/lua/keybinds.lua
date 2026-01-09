local wk = require('which-key')

local neotest = require('neotest')
local smart_split = require('smart-splits')
local snacks = require('snacks')

-- Misc top level bindings
wk.add({
  { '<leader><Tab>', '<cmd>edit #<cr>', desc = 'Switch to last buffer' },
  { '<leader>/', snacks.terminal.toggle, desc = 'Toggle terminal' },
  { '<leader>/', snacks.terminal.toggle, desc = 'Toggle terminal', mode = 't' },

  -- Pane Navigation with Smart Splits
  { '<A-h>', smart_split.resize_left },
  { '<A-j>', smart_split.resize_down },
  { '<A-k>', smart_split.resize_up },
  { '<A-l>', smart_split.resize_right },

  -- Moving between splits
  { '<C-h>', smart_split.move_cursor_left },
  { '<C-j>', smart_split.move_cursor_down },
  { '<C-k>', smart_split.move_cursor_up },
  { '<C-l>', smart_split.move_cursor_right },
  { '<C-\\>', smart_split.move_cursor_previous },

  -- Terminal mode navigation
  { '<C-h>', smart_split.move_cursor_left, mode = 't' },
  { '<C-j>', smart_split.move_cursor_down, mode = 't' },
  { '<C-k>', smart_split.move_cursor_up, mode = 't' },
  { '<C-l>', smart_split.move_cursor_right, mode = 't' },

  -- Visual mode navigation
  { '<C-h>', smart_split.move_cursor_left, mode = 'v' },
  { '<C-j>', smart_split.move_cursor_down, mode = 'v' },
  { '<C-k>', smart_split.move_cursor_up, mode = 'v' },
  { '<C-l>', smart_split.move_cursor_right, mode = 'v' },

  -- Swapping buffers between windows
  { '<leader><leader>h', smart_split.swap_buf_left },
  { '<leader><leader>j', smart_split.swap_buf_down },
  { '<leader><leader>k', smart_split.swap_buf_up },
  { '<leader><leader>l', smart_split.swap_buf_right },

  -- Open explorer
  { '<leader>`', snacks.explorer.open },
})

-- Fuzzy Finding
local function files_hidden()
  snacks.picker.files({
    finder = 'files',
    format = 'file',
    show_empty = true,
    hidden = true,
    ignored = true,
    follow = false,
    supports_live = true,
  })
end

wk.add({
  { '<leader>f', group = 'Find' },
  { '<leader>f?', snacks.picker.help, desc = 'Find help tags' },
  { '<leader>fb', snacks.picker.buffers, desc = 'Find buffer' },
  { '<leader>ff', snacks.picker.files, desc = 'Find file' },
  { '<leader>fg', snacks.picker.grep, desc = 'Find line in file' },
  { '<leader>fh', files_hidden, desc = 'Find file (including hidden)' },
  { '<leader>fm', snacks.picker.marks, desc = 'Find marks' },
  { '<leader>fr', snacks.picker.recent, desc = 'Find recent files' },
  { '<leader>fc', snacks.picker.command_history, desc = 'Find recent commands' },
  { '<leader>fd', snacks.picker.diagnostics_buffer, desc = 'Find buffer diagnostics' },
  { '<leader>fD', snacks.picker.diagnostics, desc = 'Find all diagnostics' },
  { '<leader>fu', snacks.picker.undo, desc = 'Find undo history' },
  { '<leader>fr', snacks.picker.registers, desc = 'Find registers' },
  { '<leader>fr', snacks.picker.resume, desc = 'Resume last search' },
  { '<leader>fp', snacks.picker.pickers, desc = 'Find pickers' },
  { '<leader>fn', snacks.picker.notifications, desc = 'Find notifications' },
  { '<leader>fGb', snacks.picker.git_branches, desc = 'Find Git branches' },
  { '<leader>fGl', snacks.picker.git_log, desc = 'Find Git log' },
  { '<leader>fGL', snacks.picker.git_log_line, desc = 'Find Git log line' },
  { '<leader>fGs', snacks.picker.git_status, desc = 'Find Git status' },
  { '<leader>fGS', snacks.picker.git_stash, desc = 'Find Git stash' },
  { '<leader>fGd', snacks.picker.git_diff, desc = 'Find Git diff (hunks)' },
  { '<leader>fGf', snacks.picker.git_log_file, desc = 'Find Git log files' },
  { '<leader>fF', snacks.picker.smart, desc = 'Smart Finder' },
  { '<leader>fr', snacks.picker.resume, desc = 'Resume last search' },
  -- TODO: enable this if we ever switch to using lazy plugin loader
  -- { '<leader>fl', snacks.picker.lazy,            desc = 'Find plugin specs' },
})

-- Get around important files easily
wk.add({
  { '<leader><leader><Tab>', group = 'Grapple' },
  { '<leader><leader><Tab>m', '<cmd>Grapple toggle<cr>', desc = 'Grapple toggle tag' },
  { '<leader><leader><Tab>M', '<cmd>Grapple toggle_tags<cr>', desc = 'Grapple open tags window' },
  { '<leader><leader><Tab>n', '<cmd>Grapple cycle_tags next<cr>', desc = 'Grapple cycle next tag' },
  { '<leader><leader><Tab>p', '<cmd>Grapple cycle_tags prev<cr>', desc = 'Grapple cycle previous tag' },
})

-- Diagnostics and Trouble.nvim
wk.add({
  { '<leader>d', group = 'Diagnostics/Trouble' },
  { '<leader>dd', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', desc = 'Trouble document diagnostics' },
  { '<leader>dl', '<cmd>Trouble lsp toggle<cr>', desc = 'Trouble document diagnostics' },
  { '<leader>de', '<cmd>Trouble lsp_definitions toggle<cr>', desc = 'Trouble definitions' },
  { '<leader>di', '<cmd>Trouble lsp_implementations toggle<cr>', desc = 'Trouble implementations' },
  { '<leader>dr', '<cmd>Trouble lsp_references toggle<cr>', desc = 'Trouble references' },
  {
    '<leader>dn',
    function()
      vim.diagnostic.jump({ count = 1, float = true })
    end,
    desc = 'Go to next diagnostic',
  },
  {
    '<leader>dp',
    function()
      vim.diagnostic.jump({ count = -1, float = true })
    end,
    desc = 'Go to previous diagnostic',
  },
})

-- Testing
wk.add({
  { '<leader>t', group = 'Testing' },
  {
    '<leader>tf',
    function()
      neotest.run.run(vim.fn.expand('%'))
    end,
    desc = 'Run tests in file',
  },
  {
    '<leader>tp',
    function()
      neotest.output_panel.toggle()
    end,
    desc = 'Toggle output panel',
  },
  {
    '<leader>ts',
    function()
      neotest.summary.toggle()
    end,
    desc = 'Toggle summary',
  },
  {
    '<leader>tt',
    function()
      neotest.run.run()
    end,
    desc = 'Run nearest test',
  },
  {
    '<leader>tw',
    function()
      neotest.watch.toggle(vim.fn.expand('%'))
    end,
    desc = 'Watch tests in file',
  },
  {
    '<leader>ta',
    function()
      neotest.run.attach()
    end,
    desc = 'Attach to running test',
  },
  {
    '<leader>tl',
    function()
      neotest.run.run_last()
    end,
    desc = 'Run last test',
  },
})

-- Language Server
wk.add({
  { 'K', vim.lsp.buf.hover, desc = 'Show hover docs' },
  { '<leader>l', group = 'LSP' },
  { '<leader>lD', snacks.picker.lsp_definitions, desc = 'Show definitions' },
  { '<leader>ld', snacks.picker.lsp_declarations, desc = 'Show declarations' },
  { '<leader>li', snacks.picker.lsp_implementations, desc = 'Show implementations' },
  { '<leader>ll', vim.lsp.buf.code_action, desc = 'Show code actions' },
  { '<leader>ls', snacks.picker.lsp_symbols, desc = 'Show buffer symbols' },
  { '<leader>lS', snacks.picker.workspace_lsp_symbols, desc = 'Show workspace symbols' },
  { '<leader>lr', snacks.picker.lsp_references, desc = 'Show references' },
  { '<leader>lt', snacks.picker.lsp_type_definitions, desc = 'Show type definition' },
  { '<leader>lf', vim.lsp.buf.format, desc = 'Format buffer' },
  { '<leader>lR', vim.lsp.buf.rename, desc = 'Rename under cursor' },
})

-- Navigate to other files
wk.add({
  { '<leader>o', group = 'Other files' },
  { '<leader>oc', '<cmd>OtherClear<cr>', desc = 'Clear the internal reference to other file' },
  { '<leader>oo', '<cmd>Other<cr>', desc = 'Open the the other file' },
  { '<leader>os', '<cmd>OtherSplit<cr>', desc = 'Open the the other file in a horizontal split' },
  { '<leader>ov', '<cmd>OtherVSplit<cr>', desc = 'Open the the other file in a vertical split' },
})

-- Claude Code
wk.add({
  { '<leader>c', group = 'Claude Code' },
})
vim.keymap.set('n', '<leader>cc', '<cmd>ClaudeCode<cr>', { desc = 'Toggle Claude' })
vim.keymap.set('n', '<leader>cf', '<cmd>ClaudeCodeFocus<cr>', { desc = 'Focus Claude' })
vim.keymap.set('n', '<leader>cr', '<cmd>ClaudeCode --resume<cr>', { desc = 'Resume Claude' })
vim.keymap.set('n', '<leader>cC', '<cmd>ClaudeCode --continue<cr>', { desc = 'Continue Claude' })
vim.keymap.set('n', '<leader>cm', '<cmd>ClaudeCodeSelectModel<cr>', { desc = 'Select Claude model' })
vim.keymap.set('n', '<leader>cb', '<cmd>ClaudeCodeAdd %<cr>', { desc = 'Add current buffer' })
vim.keymap.set('n', '<leader>ca', '<cmd>ClaudeCodeDiffAccept<cr>', { desc = 'Accept diff' })
vim.keymap.set('n', '<leader>cd', '<cmd>ClaudeCodeDiffDeny<cr>', { desc = 'Deny diff' })
vim.keymap.set('v', '<leader>cs', '<cmd>ClaudeCodeSend<cr>', { desc = 'Send to Claude' })
-- Set Claude Code tree add keymap only for file browser filetypes
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'NvimTree', 'neo-tree', 'oil', 'minifiles' },
  callback = function()
    vim.keymap.set('n', '<leader>cs', '<cmd>ClaudeCodeTreeAdd<cr>', { desc = 'Add file', buffer = true })
    vim.keymap.set('n', '<leader>cS', function()
      vim.cmd('ClaudeCodeTreeAdd')
      vim.cmd('ClaudeCodeFocus')
      -- Wait 100ms for focus to complete, then send enter
      vim.defer_fn(function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
      end, 100)
    end, { desc = 'Add file and send', buffer = true })
  end,
})

-- Git keybindings
local gs = require('gitsigns')
local gsa = require('gitsigns.actions')
local gl = require('gitlinker')

wk.add({
  { '<leader>g', group = 'Git' },
  { '<leader>gg', '<cmd>Neogit<cr>', desc = 'Open Neogit UI' },
  {
    '<leader>gb',
    function()
      snacks.git.blame_line()
    end,
    desc = 'Blame Current Line',
  },
  {
    '<leader>gn',
    function()
      gsa.next_hunk()
    end,
    desc = 'Go to next hunk',
  },
  {
    '<leader>gp',
    function()
      gsa.prev_hunk()
    end,
    desc = 'Go to previous hunk',
  },
  {
    '<leader>gr',
    function()
      gs.reset_hunk()
    end,
    desc = 'Reset hunk',
  },
  {
    '<leader>gs',
    function()
      gs.stage_hunk()
    end,
    desc = 'Stage hunk',
  },
  {
    '<leader>gu',
    function()
      gs.undo_stage_hunk()
    end,
    desc = 'Unstage hunk',
  },
  {
    '<leader>go',
    function()
      snacks.gitbrowse()
    end,
    desc = 'Open current file in browser',
  },
  {
    '<leader>gy',
    function()
      gl.link({
        -- GitLinker hard codes to the + register which doesn't work over ssh
        -- action = gla.clipboard,
        action = function(url)
          vim.fn.setreg('"', url)
        end,
        lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
        lend = vim.api.nvim_buf_get_mark(0, '>')[1],
      })
    end,
    desc = 'Copy permalink to clipboard',
  },
})

wk.add({
  mode = { 'v' },
  { '<leader>g', group = 'Git' },
  {
    '<leader>gr',
    function()
      gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
    end,
    desc = 'Reset hunk',
  },
  {
    '<leader>gs',
    function()
      gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
    end,
    desc = 'Stage hunk',
  },
  {
    '<leader>gy',
    function()
      gl.link({
        -- GitLinker hard codes to the + register which doesn't work over ssh
        -- action = gla.clipboard,
        action = function(url)
          vim.fn.setreg('"', url)
        end,
        lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
        lend = vim.api.nvim_buf_get_mark(0, '>')[1],
      })
    end,
    desc = 'Copy permalink to clipboard',
  },
})

-- Local leader keybinding for formatting current file with treefmt
vim.keymap.set('n', '<localleader>f', '<cmd>Treefmt<cr>', { desc = 'Format current file with treefmt' })

-- Lua-specific keybindings
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'lua',
  callback = function()
    wk.add({
      buffer = true,
      {
        '<localleader>e',
        '<cmd>LuaEval<cr>',
        desc = 'Evaluate current file/selection',
        mode = { 'n', 'v' },
      },
    })
  end,
})
