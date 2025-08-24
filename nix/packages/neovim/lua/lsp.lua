-- Helper function for cmp/LuaSnip bindings
local has_words_before = function()
  -- selene: allow(incorrect_standard_library_use)
  unpack = unpack or table.unpack
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match('%s') == nil
end

local cmp = require('cmp')
local luasnip = require('luasnip')
local lspconfig = require('lspconfig')
local navic = require('nvim-navic')

-- Setup completion
cmp.setup({
  snippet = {
    expand = function(args)
      require('luasnip').lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.abort(),
    ['<CR>'] = cmp.mapping.confirm({ select = true }),
    ['<Tab>'] = cmp.mapping(function(fallback)
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
  }),
  window = {
    completion = cmp.config.window.bordered(),
    documentation = cmp.config.window.bordered(),
  },
  sources = cmp.config.sources({
    { name = 'path' },
    { name = 'nvim_lsp', keyword_length = 2 },
    { name = 'luasnip', keyword_length = 3 },
  }, {
    { name = 'buffer', keyword_length = 4 },
  }),
})

-- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline({ '/', '?' }, {
  mapping = cmp.mapping.preset.cmdline(),
  sources = {
    { name = 'buffer' },
  },
})

-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline(':', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = cmp.config.sources({
    { name = 'path' },
  }, {
    { name = 'cmdline' },
  }),
})

-- Setup Language Servers

-- Set the default capabilities
local lsp_defaults = lspconfig.util.default_config
lsp_defaults.capabilities =
  vim.tbl_deep_extend('force', lsp_defaults.capabilities, require('cmp_nvim_lsp').default_capabilities())

-- Attach navic
lsp_defaults.on_attach = function(client, bufnr)
  -- selene: allow(multiple_statements)
  if client.server_capabilities.documentSymbolProvider then
    navic.attach(client, bufnr)
  end
end

-- Autoformat before save
vim.api.nvim_create_augroup('AutoFormatting', {})
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*',
  group = 'AutoFormatting',
  callback = function()
    vim.lsp.buf.format()
  end,
})

-- Setup some language servers
-- Config stolen from lsp-zero.nvim, makes Lua work good with Neovim
-- See: https://github.com/VonHeikemen/lsp-zero.nvim/blob/dev-v3/lua/lsp-zero/server.lua#L203-L233
local lua_ls_config = function()
  local runtime_path = vim.split(package.path, ';')
  table.insert(runtime_path, 'lua/?.lua')
  table.insert(runtime_path, 'lua/?/init.lua')

  return {
    settings = {
      Lua = {
        -- Disable telemetry
        telemetry = { enable = false },
        runtime = {
          -- Tell the language server which version of Lua you're using
          -- (most likely LuaJIT in the case of Neovim)
          version = 'LuaJIT',
          path = runtime_path,
        },
        diagnostics = {
          -- Get the language server to recognize the `vim` global
          globals = { 'vim' },
        },
        workspace = {
          checkThirdParty = false,
          library = {
            -- Make the server aware of Neovim runtime files
            vim.fn.expand('$VIMRUNTIME/lua'),
            vim.fn.stdpath('config') .. '/lua',
          },
        },
      },
    },
  }
end
-- Configure lua_ls to use stylua for formatting
local lua_config = lua_ls_config()
lua_config.settings.Lua.format = {
  enable = true, -- Disable built-in formatter
}
-- Override the formatting handler to use stylua
lua_config.on_attach = function(client, bufnr)
  if client.server_capabilities.documentSymbolProvider then
    navic.attach(client, bufnr)
  end

  -- Override LSP formatting to use stylua
  client.server_capabilities.documentFormattingProvider = true
  vim.lsp.handlers['textDocument/formatting'] = function(_, _, ctx)
    if ctx.client_id == client.id then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      vim.fn.system('stylua ' .. vim.fn.shellescape(bufname))
      vim.cmd('edit') -- Reload to show changes
    end
  end
end
lspconfig.lua_ls.setup(lua_config) -- Lua
lspconfig.nil_ls.setup({
  settings = {
    ['nil'] = {
      formatting = {
        command = { 'alejandra' },
      },
    },
  },
})
lspconfig.gopls.setup({})
lspconfig.terraformls.setup({})
lspconfig.ruby_lsp.setup({})
lspconfig.rubocop.setup({})
lspconfig.gleam.setup({})
lspconfig.ts_ls.setup({})
vim.lsp.enable('sourcekit')
lspconfig.yamlls.setup({
  settings = {
    yaml = {
      format = {
        enable = true,
      },
    },
  },
})
lspconfig.emmet_ls.setup({
  filetypes = { 'css', 'html', 'javascript', 'heex', 'htmldjango' },
})
-- lspconfig.elixirls.setup({
--   cmd = { os.getenv('ELIXIRLS_CMD') },
-- })
-- lspconfig.nextls.setup({
--   cmd = { os.getenv('NEXTLS_CMD'), '--stdio' },
-- })
lspconfig.rust_analyzer.setup({
  settings = {
    ['rust-analyzer'] = {
      check = {
        command = 'clippy',
      },
    },
  },
})

-- Setup html language server
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.completion.completionItem.snippetSupport = true
require('lspconfig').html.setup({
  capabilities = capabilities,
  filetypes = { 'html', 'heex', 'htmldjango', 'templ' },
})
