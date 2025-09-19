-- Fresh start: Close all buffers but stay open
vim.api.nvim_create_user_command('BdeleteAll', function()
  vim.cmd('bufdo bdelete')
end, { desc = 'Close all buffers, but stay open' })

-- Files with hidden support
vim.api.nvim_create_user_command('FilesHidden', function()
  local snacks = require('snacks')
  snacks.picker.files({
    finder = 'files',
    format = 'file',
    show_empty = true,
    hidden = true,
    ignored = true,
    follow = false,
    supports_live = true,
  })
end, { desc = 'Find files including hidden ones' })

-- Claude Code tree add and send command
vim.api.nvim_create_user_command('ClaudeTreeAddSend', function()
  vim.cmd('ClaudeCodeTreeAdd')
  vim.cmd('ClaudeCodeFocus')
  -- Wait 100ms for focus to complete, then send enter
  vim.defer_fn(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
  end, 100)
end, { desc = 'Add file to Claude and send' })

-- Lua debug run command
vim.api.nvim_create_user_command('LuaDebugRun', function()
  require('snacks').debug.run()
end, { desc = 'Run current Lua file/selection' })

-- Lua eval command (only available for lua files)
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'lua',
  callback = function()
    vim.api.nvim_buf_create_user_command(0, 'LuaEval', function()
      require('snacks').debug.run()
    end, { desc = 'Evaluate current Lua file/selection', range = true })
  end,
})

-- LSP Capabilities display
vim.api.nvim_create_user_command('LspCapabilities', function()
  local snacks = require('snacks')

  local function get_lsp_capabilities_data()
    local content_lines = {}
    table.insert(content_lines, '# LSP Capabilities')
    table.insert(content_lines, '')

    local clients = vim.lsp.get_clients({ bufnr = 0 })

    if #clients == 0 then
      table.insert(content_lines, 'No LSP clients are currently running.')
    else
      for _, client in pairs(clients) do
        if client.name ~= 'null-ls' then
          table.insert(content_lines, '## ' .. client.name)
          table.insert(content_lines, '')

          local capAsList = {}
          for key, value in pairs(client.server_capabilities) do
            if value and key:find('Provider') then
              local capability = key:gsub('Provider$', '')
              table.insert(capAsList, '- ' .. capability)
            end
          end

          if #capAsList == 0 then
            table.insert(content_lines, 'No capabilities found.')
          else
            table.sort(capAsList) -- sorts alphabetically
            for _, cap in ipairs(capAsList) do
              table.insert(content_lines, cap)
            end
          end
          table.insert(content_lines, '')
        end
      end
    end

    return content_lines
  end

  local content_lines = get_lsp_capabilities_data()

  snacks.win({
    text = table.concat(content_lines, '\n'),
    ft = 'markdown',
    title = 'LSP Capabilities',
    wo = {
      wrap = true,
    },
  })
end, { desc = 'Show LSP server capabilities' })

-- Dashboard open
vim.api.nvim_create_user_command('Dashboard', function()
  require('snacks').dashboard.open()
end, { desc = 'Open dashboard' })

-- Nix Install (for nixos-configs directory) - only available in nixos-configs directory
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
  pattern = vim.fn.expand('~/nixos-configs') .. '/*',
  callback = function()
    vim.api.nvim_buf_create_user_command(0, 'NixInstall', function()
      local snacks = require('snacks')
      snacks.terminal('nix-activate-config; echo "Press any key to close..."; read -n 1', {
        cwd = vim.fn.expand('~/nixos-configs'),
        win = {
          position = 'bottom',
          height = 0.4,
        },
        auto_close = true,
      })
    end, { desc = 'Install Nix configuration (nix-activate-config)' })
  end,
})

-- Treefmt command for current file or specified paths
if vim.fn.executable('treefmt') == 1 then
  vim.api.nvim_create_user_command('Treefmt', function(opts)
    local snacks = require('snacks')
    local args = opts.args
    local cmd

    if args == '' then
      -- Format current file
      local current_file = vim.fn.expand('%:p')
      if current_file == '' then
        snacks.notifier.notify('No file to format', { level = 'warn' })
        return
      end
      cmd = 'treefmt ' .. vim.fn.shellescape(current_file)
    else
      -- Format specified paths
      local paths = {}
      for path in string.gmatch(args, '%S+') do
        table.insert(paths, vim.fn.shellescape(path))
      end
      cmd = 'treefmt ' .. table.concat(paths, ' ')
    end

    local output = vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
      if output ~= '' then
        print(output)
      end
    else
      snacks.notifier.notify('Treefmt failed: ' .. output, { level = 'error' })
    end
  end, {
    nargs = '*',
    desc = 'Format a file with treefmt',
    complete = function(arg_lead)
      return vim.fn.getcompletion(arg_lead, 'file')
    end,
  })

  -- TreefmtAll command for entire project
  vim.api.nvim_create_user_command('TreefmtAll', function()
    local snacks = require('snacks')
    local output = vim.fn.system('treefmt')
    if vim.v.shell_error == 0 then
      if output ~= '' then
        print(output)
      end
    else
      snacks.notifier.notify('Treefmt failed: ' .. output, { level = 'error' })
    end
  end, { desc = 'Format all files with treefmt' })
end
