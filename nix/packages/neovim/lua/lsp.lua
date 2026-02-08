local navic = require('nvim-navic')
local blink = require('blink.cmp')
local mini_icons = require('mini.icons')

---- Setup Completion ----

-- Load some additional providers
require('blink-cmp-git')

-- Main setup
blink.setup({
  keymap = { preset = 'default' },

  appearance = {
    nerd_font_variant = 'mono',
  },

  completion = {
    documentation = { auto_show = false },

    -- Draw the menu with mini.icons and lspkind
    menu = {
      draw = {
        columns = { { 'kind_icon', 'label', 'label_description', gap = 1 }, { 'kind' } },
        components = {
          kind_icon = {
            text = function(ctx)
              if vim.tbl_contains({ 'Path' }, ctx.source_name) then
                local mini_icon, _ = mini_icons.get(ctx.item.data.type, ctx.label)
                if mini_icon then
                  return mini_icon .. ctx.icon_gap
                end
              end

              local icon = require('lspkind').symbolic(ctx.kind, { mode = 'symbol' })
              return icon .. ctx.icon_gap
            end,

            -- Optionally, use the highlight groups from mini.icons
            -- You can also add the same function for `kind.highlight` if you want to
            -- keep the highlight groups in sync with the icons.
            highlight = function(ctx)
              if vim.tbl_contains({ 'Path' }, ctx.source_name) then
                local mini_icon, mini_hl = mini_icons.get(ctx.item.data.type, ctx.label)
                if mini_icon then
                  return mini_hl
                end
              end
              return ctx.kind_hl
            end,
          },
          kind = {
            -- Optional, use highlights from mini.icons
            highlight = function(ctx)
              if vim.tbl_contains({ 'Path' }, ctx.source_name) then
                local mini_icon, mini_hl = mini_icons.get(ctx.item.data.type, ctx.label)
                if mini_icon then
                  return mini_hl
                end
              end
              return ctx.kind_hl
            end,
          },
        },
      },
    },
  },

  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer', 'git' },
    providers = {
      lsp = {
        score_offset = 1,
      },
      snippets = {
        score_offset = 2,
      },
      buffer = {
        score_offset = 3,
        min_keyword_length = 3,
      },
      path = {
        score_offset = 4,
      },
      git = {
        module = 'blink-cmp-git',
        name = 'Git',
        opts = {},
        -- This should ALWAYS go last
        score_offset = -10000,
        min_keyword_length = 4,
      },
    },
  },

  signature = { enabled = true },

  fuzzy = { implementation = 'prefer_rust_with_warning' },
})

---- Setup Language Servers ----

-- Set the default capabilities
vim.lsp.config('*', {
  capabilities = vim.tbl_deep_extend(
    'force',
    vim.lsp.protocol.make_client_capabilities(),
    blink.get_lsp_capabilities({}, false)
  ),
  on_attach = function(client, bufnr)
    -- Attach Navic
    -- selene: allow(multiple_statements)
    if client.server_capabilities.documentSymbolProvider then
      navic.attach(client, bufnr)
    end
  end,
})

vim.lsp.config('expert', {
  cmd = { 'expert', '--stdio' },
  root_markers = { 'mix.exs' },
  filetypes = { 'elixir', 'eelixir', 'heex', 'surface' },
})

vim.lsp.config('emmet_ls', {
  filetypes = { 'css', 'html', 'javascript', 'heex', 'htmldjango' },
})

vim.lsp.config('lexical', {
  cmd = { 'lexical' },
})

vim.lsp.config('rust_analyzer', {
  settings = {
    ['rust-analyzer'] = {
      check = {
        command = 'clippy',
      },
    },
  },
})

vim.lsp.config('nil_ls', {
  settings = {
    ['nil'] = {
      formatting = {
        command = { 'alejandra' },
      },
    },
  },
})

vim.lsp.config('hls', {
  filetypes = { 'haskell', 'lhaskell', 'cabal' },
})

vim.lsp.enable('sourcekit')
vim.lsp.enable('nil_ls')
vim.lsp.enable('nixd')
vim.lsp.enable('expert')
vim.lsp.enable('nextls')
vim.lsp.enable('lua_ls')
vim.lsp.enable('emmet_ls')
vim.lsp.enable('lexical')
vim.lsp.enable('rust_analyzer')
vim.lsp.enable('unison')
vim.lsp.enable('hls')

-- Python
vim.lsp.enable('basedpyright')
vim.lsp.enable('ruff')

-- Autoformat before save
vim.api.nvim_create_augroup('AutoFormatting', {})
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*',
  group = 'AutoFormatting',
  callback = function()
    vim.lsp.buf.format()
  end,
})

-- -- Setup some language servers
-- -- Config stolen from lsp-zero.nvim, makes Lua work good with Neovim
-- -- See: https://github.com/VonHeikemen/lsp-zero.nvim/blob/dev-v3/lua/lsp-zero/server.lua#L203-L233
-- local lua_ls_config = function()
--   local runtime_path = vim.split(package.path, ';')
--   table.insert(runtime_path, 'lua/?.lua')
--   table.insert(runtime_path, 'lua/?/init.lua')
--
--   return {
--     settings = {
--       Lua = {
--         -- Disable telemetry
--         telemetry = { enable = false },
--         runtime = {
--           -- Tell the language server which version of Lua you're using
--           -- (most likely LuaJIT in the case of Neovim)
--           version = 'LuaJIT',
--           path = runtime_path,
--         },
--         diagnostics = {
--           -- Get the language server to recognize the `vim` global
--           globals = { 'vim' },
--         },
--         workspace = {
--           checkThirdParty = false,
--           library = {
--             -- Make the server aware of Neovim runtime files
--             vim.fn.expand('$VIMRUNTIME/lua'),
--             vim.fn.stdpath('config') .. '/lua',
--           },
--         },
--       },
--     },
--   }
-- end
-- -- Configure lua_ls to use stylua for formatting
-- local lua_config = lua_ls_config()
-- lua_config.settings.Lua.format = {
--   enable = true, -- Disable built-in formatter
-- }
-- -- Override the formatting handler to use stylua
-- lua_config.on_attach = function(client, bufnr)
--   if client.server_capabilities.documentSymbolProvider then
--     navic.attach(client, bufnr)
--   end
--
--   -- Override LSP formatting to use stylua
--   client.server_capabilities.documentFormattingProvider = true
--   vim.lsp.handlers['textDocument/formatting'] = function(_, _, ctx)
--     if ctx.client_id == client.id then
--       local bufname = vim.api.nvim_buf_get_name(bufnr)
--       vim.fn.system('stylua ' .. vim.fn.shellescape(bufname))
--       vim.cmd('edit') -- Reload to show changes
--     end
--   end
-- end
-- lspconfig.lua_ls.setup(lua_config) -- Lua
-- lspconfig.nil_ls.setup({
--   settings = {
--     ['nil'] = {
--       formatting = {
--         command = { 'alejandra' },
--       },
--     },
--   },
-- })
-- lspconfig.gopls.setup({})
-- lspconfig.terraformls.setup({})
-- lspconfig.ruby_lsp.setup({})
-- lspconfig.rubocop.setup({})
-- lspconfig.gleam.setup({})
-- lspconfig.ts_ls.setup({})
-- vim.lsp.enable('sourcekit')
-- lspconfig.yamlls.setup({
--   settings = {
--     yaml = {
--       format = {
--         enable = true,
--       },
--     },
--   },
-- })
-- lspconfig.emmet_ls.setup({
--   filetypes = { 'css', 'html', 'javascript', 'heex', 'htmldjango' },
-- })
-- -- lspconfig.elixirls.setup({
-- --   cmd = { os.getenv('ELIXIRLS_CMD') },
-- -- })
-- -- lspconfig.nextls.setup({
-- --   cmd = { os.getenv('NEXTLS_CMD'), '--stdio' },
-- -- })
-- lspconfig.rust_analyzer.setup({
--   settings = {
--     ['rust-analyzer'] = {
--       check = {
--         command = 'clippy',
--       },
--     },
--   },
-- })
--
-- -- Setup html language server
-- local capabilities = vim.lsp.protocol.make_client_capabilities()
-- capabilities.textDocument.completion.completionItem.snippetSupport = true
-- require('lspconfig').html.setup({
--   capabilities = capabilities,
--   filetypes = { 'html', 'heex', 'htmldjango', 'templ' },
-- })
