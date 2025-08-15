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
  { '<leader>fF', snacks.picker.smart, desc = 'Smart Finder' },
  { '<leader>fr', snacks.picker.resume, desc = 'Resume last search' },
  -- TODO: enable this if we ever switch to using lazy plugin loader
  -- { '<leader>fl', snacks.picker.lazy,            desc = 'Find plugin specs' },
})

-- Diagnostics and Trouble.nvim
wk.add({
  { '<leader>d', group = 'Diagnostics/Trouble' },
  { '<leader>dd', '<cmd>TroubleToggle document_diagnostics<cr>', desc = 'Trouble document diagnostics' },
  { '<leader>de', '<cmd>TroubleToggle lsp_definitions<cr>', desc = 'Trouble definitions' },
  { '<leader>di', '<cmd>TroubleToggle lsp_implementations<cr>', desc = 'Trouble implementations' },
  {
    '<leader>dn',
    function()
      vim.diagnostic.jump({ count = 1 })
    end,
    desc = 'Go to next diagnostic',
  },
  {
    '<leader>dp',
    function()
      vim.diagnostic.jump({ count = -1 })
    end,
    desc = 'Go to previous diagnostic',
  },
  { '<leader>dr', '<cmd>TroubleToggle lsp_references<cr>', desc = 'Trouble references' },
  { '<leader>dt', '<cmd>TroubleToggle<cr>', desc = 'Time for trouble' },
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
  { '<leader>ls', snacks.picker.workspace_lsp_symbols, desc = 'Show workspace symbols' },
  { '<leader>lr', snacks.picker.lsp_references, desc = 'Show references' },
  { '<leader>lt', snacks.picker.lsp_type_definitions, desc = 'Show type definition' },
  { '<leader>lf', vim.lsp.buf.format, desc = 'Format buffer' },
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

-- GenAI with Parrot
-- wk.add({
--   { '<leader>c', group = 'GenAI' },
--   { '<leader>cc', '<cmd>PrtChatNew popup<cr>', desc = 'Open a new chat' },
--   { '<leader>c<Tab>', '<cmd>PrtChatToggle popup<cr>', desc = 'Toggle chat' },
--   { '<leader>cP', '<cmd>PrtChatPaste popup<cr>', desc = 'Paste visual selection into latest chat' },
--   { '<leader>cf', '<cmd>PrtChatFinder<cr>', desc = 'Fuzzy search chat files using fzf' },
--   { '<leader>cd', '<cmd>PrtChatDelete<cr>', desc = 'Delete current chat file' },
--   { '<leader>cs', '<cmd>PrtStop<cr>', desc = 'Interrupt ongoing respond' },
--   { '<leader>cS', '<cmd>PrtStatus<cr>', desc = 'Prints current provider and model selection' },
--   { '<leader>cr', '<cmd>PrtRewrite<cr>', desc = 'Rewrites the visual selection based on a prompt' },
--   { '<leader>ca', '<cmd>PrtAppend<cr>', desc = 'Append text to visual selection based on a prompt' },
--   { '<leader>cp', '<cmd>PrtPrepend<cr>', desc = 'Prepend text to visual selection based on a prompt' },
--   { '<leader>cR', '<cmd>PrtRetry<cr>', desc = 'Repeats the last rewrite/append/prepend' },
-- })

-- wk.add({
--   mode = { 'v' },
--   { '<leader>c',  group = 'GenAI' },
--   { '<leader>cc', ":'<,'>PrtChatNew popup<cr>",   desc = 'Open a new chat' },
--   { '<leader>cp', ":'<,'>PrtChatPaste popup<cr>", desc = 'Paste visual selection into latest chat' },
--   { '<leader>cr', ":'<,'>PrtRewrite<cr>",         desc = 'Rewrites the visual selection based on a prompt' },
--   { '<leader>ca', ":'<,'>PrtAppend<cr>",          desc = 'Append text to visual selection based on a prompt' },
--   { '<leader>cp', ":'<,'>PrtPrepend<cr>",         desc = 'Prepend text to visual selection based on a prompt' },
-- })

-- Git keybindings
local gs = require('gitsigns')
local gsa = require('gitsigns.actions')
local gl = require('gitlinker')
-- local gla = require('gitlinker.actions')

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

-- Local leader keybinding for Lua evaluation in nixos-configs directory
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = vim.fn.expand('~/nixos-configs') .. '/**/*.lua',
  callback = function()
    vim.keymap.set('v', '<localleader>e', function()
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local lines = vim.fn.getline(start_pos[2], end_pos[2])
      if type(lines) == 'string' then
        lines = { lines }
      end

      if #lines == 1 then
        lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
      else
        lines[1] = lines[1]:sub(start_pos[3])
        lines[#lines] = lines[#lines]:sub(1, end_pos[3])
      end

      local code = table.concat(lines, '\n')
      local chunk = load(code)
      if not chunk then
        print('Error: Failed to compile Lua code')
        return
      end
      local success, result = pcall(chunk)

      if success then
        if result ~= nil then
          print(vim.inspect(result))
        else
          print('Code executed successfully')
        end
      else
        print('Error: ' .. tostring(result))
      end
    end, { desc = 'Evaluate Lua selection', buffer = true })
  end,
})
