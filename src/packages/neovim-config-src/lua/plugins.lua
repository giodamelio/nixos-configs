local plugins = {
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
    opts = {},
    config = true,
  },

  -- Fuzzy find all the things
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local wk = require('which-key')
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

      -- Allow opening telescope results in Trouble
      telescope.setup({
        defaults = {
          mappings = {
            i = { ['<c-t>'] = trouble.open_with_trouble },
            n = { ['<c-t>'] = trouble.open_with_trouble },
          },
        },
      })
    end
  },

  -- Setup Language Server, Autocomplete and Snippets
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Autocompletion
      { 'hrsh7th/nvim-cmp' },
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'hrsh7th/cmp-buffer' },
      { 'hrsh7th/cmp-path' },
      { 'hrsh7th/cmp-cmdline' },

      -- Snippets
      { 'L3MON4D3/luasnip' },
      { 'saadparwaiz1/cmp_luasnip' },
      { 'rafamadriz/friendly-snippets' },

      -- Code Context
      { 'SmiteshP/nvim-navic' }
    },
    config = function()
      -- Helper function for cmp/LuaSnip bindings
      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match('%s') == nil
      end

      local wk = require('which-key')
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
        sources = cmp.config.sources(
          {
            { name = 'path', },
            { name = 'nvim_lsp', keyword_length = 2, },
            { name = 'luasnip',  keyword_length = 3, },
          }, {
            { name = 'buffer', keyword_length = 4, },
          }
        ),
      })

      -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline({ '/', '?' }, {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = 'buffer' }
        }
      })

      -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources(
          {
            { name = 'path' }
          }, {
            { name = 'cmdline' }
          }
        )
      })

      -- Setup Language Servers

      -- Set the default capabilities
      local lsp_defaults = lspconfig.util.default_config
      lsp_defaults.capabilities = vim.tbl_deep_extend(
        'force',
        lsp_defaults.capabilities,
        require('cmp_nvim_lsp').default_capabilities()
      )

      -- Attach navic
      lsp_defaults.on_attach = function(client, bufnr)
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
                globals = { 'vim' }
              },
              workspace = {
                checkThirdParty = false,
                library = {
                  -- Make the server aware of Neovim runtime files
                  vim.fn.expand('$VIMRUNTIME/lua'),
                  vim.fn.stdpath('config') .. '/lua'
                }
              }
            }
          }
        }
      end
      lspconfig.lua_ls.setup(lua_ls_config()) -- Lua
      lspconfig.nil_ls.setup({})
      lspconfig.rust_analyzer.setup({})

      -- Setup some LSP keybindings
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

      -- Load Snippets
      require('luasnip.loaders.from_vscode').lazy_load()
    end
  },

  -- Treesitter
  {
    'nvim-treesitter/nvim-treesitter',
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
      })
    end
  },

  -- Rainbow delimiters with Treesitter
  {
    'hiphish/rainbow-delimiters.nvim',
    config = function()
      local rainbow_delimiters = require('rainbow-delimiters')
      local setup = require('rainbow-delimiters.setup')
      setup({
        strategy = {
          [''] = rainbow_delimiters.strategy['global'],
          vim = rainbow_delimiters.strategy['local'],
        },
        query = {
          [''] = 'rainbow-delimiters',
          lua = 'rainbow-blocks',
        },
        highlight = {
          'RainbowDelimiterRed',
          'RainbowDelimiterYellow',
          'RainbowDelimiterBlue',
          'RainbowDelimiterOrange',
          'RainbowDelimiterGreen',
          'RainbowDelimiterViolet',
          'RainbowDelimiterCyan',
        },
      })
    end
  },

  -- Status bar
  {
    'nvim-lualine/lualine.nvim',
    dependencies = {
      { 'kyazdani42/nvim-web-devicons' },
      { 'arkav/lualine-lsp-progress' }
    },
    config = function()
      local lualine = require('lualine')
      local default_config = lualine.get_config()

      -- Enable lualine
      local config = vim.tbl_deep_extend('force', default_config, {
        sections = {
          lualine_c = { 'filename', 'lsp_progress' }
        },
        winbar = {
          lualine_c = {
            {
              'navic',
              color_correction = nil,
              navic_opts = nil
            }
          }
        },
        -- Show some help when the tabline is open, I always forget the keys...
        tabline = {
          lualine_a = { { 'tabs', mode = 2 }, },
          lualine_x = { '"[next tab] gt, [prev tab] gT, [close tab] :tabclose"' },
        },
      })
      lualine.setup(config)

      -- Hide mode display in the command bar since lualine shows it
      vim.opt.showmode = false

      -- Only show the tabline if there is more then one tab
      vim.opt.showtabline = 1
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
          n = { function() vim.diagnostic.goto_next() end, 'Go to next diagnostic' },
          p = { function() vim.diagnostic.goto_prev() end, 'Go to previous diagnostic' },
        },
        t = { '<cmd>TroubleToggle document_diagnostics<cr>', 'Trouble document diagnostics' },
      }, { prefix = '<leader>' })
    end
  },

  -- Show git status in gutter
  {
    'lewis6991/gitsigns.nvim',
    dependencies = {
      { 'linrongbin16/gitlinker.nvim' }
    },
    config = function()
      local gs = require('gitsigns')
      local gsa = require('gitsigns.actions')
      local gl = require('gitlinker')
      local gla = require('gitlinker.actions')
      local wk = require('which-key')

      gs.setup({
        current_line_blame = true,
      })

      gl.setup({
        mapping = nil
      })

      -- Setup some keybindings
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
          y = { function()
            gl.link({
              -- GitLinker hard codes to the + register which doesn't work over ssh
              -- action = gla.clipboard,
              action = function(url)
                vim.fn.setreg('"', url)
              end,
              lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
              lend = vim.api.nvim_buf_get_mark(0, '>')[1]
            })
          end, 'Copy permalink to clipboard' },
        },
      }, { prefix = '<leader>' })

      -- Some visual mode keybindings
      -- TODO: these seem to be broken
      wk.register({
        g = {
          name = 'Git',
          s = { function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, 'Stage hunk' },
          r = { function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, 'Reset hunk' },
          y = { function()
            gl.link({
              -- GitLinker hard codes to the + register which doesn't work over ssh
              -- action = gla.clipboard,
              action = function(url)
                vim.fn.setreg('"', url)
              end,
              lstart = vim.api.nvim_buf_get_mark(0, '<')[1],
              lend = vim.api.nvim_buf_get_mark(0, '>')[1]
            })
          end, 'Copy permalink to clipboard' },
        },
      }, { prefix = '<leader>', mode = 'v' })
    end
  },

  {
    'jackMort/ChatGPT.nvim',
    dependencies = {
      'MunifTanjim/nui.nvim',
    },
    event = 'VeryLazy',
    opts = {
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
      popup_input = {
        submit = 'Enter',
      },
    },
    config = true,
  },

  -- Move/create/delete files directly in a vim buffer
  {
    'stevearc/oil.nvim',
    opts = {
      columns = { 'icon', 'permissions', 'size' }
    },
    config = true,
  },

  -- Deal with pairs of things
  {
    'kylechui/nvim-surround',
    event = 'VeryLazy',
    config = true,
  },

  -- Better comments
  {
    'numToStr/comment.nvim',
    config = true,
  },

  -- Show marks in the sign
  {
    'chentoast/marks.nvim',
    config = true,
  },

  {
    'arnamak/stay-centered.nvim',
    config = true,
  },

  {
    'NeogitOrg/neogit',
    config = true
  },

  -- Do a Unix to it!
  { 'tpope/vim-eunuch' },

  -- Add a well behaved :Bdelete (keeps splits etc...)
  { 'famiu/bufdelete.nvim' },
}

-- Do a crazy dev mode hack if we are useing Nix
-- Basically this sets all the plugins as being in development mode,
-- then uses linkFarm to generate a dir with all the plugins symlinked in the nix store.
-- It also changes the lockfile to be in /tmp, since we don't need it on Nix anyways
if os.getenv('NIX_PATH') then
  -- Add `dev = true` to each plugin
  for _, plugin in ipairs(plugins) do
    plugin.dev = true

    -- Handle the plugin dependencies
    if plugin.dependencies then
      local transformed_deps = {}
      for _, plugin_dep in ipairs(plugin.dependencies) do
        -- If it is a bare string dep, convert it to a table version
        if type(plugin_dep) == "string" then
          table.insert(transformed_deps, {
            plugin_dep,
            dev = true
          })
        else
          plugin_dep.dev = true
          table.insert(transformed_deps, plugin_dep)
        end
      end
      plugin.dependencies = transformed_deps
    end
  end

  return require('lazy').setup(plugins, {
    lockfile = '/tmp/lazy-lock.json',
    dev = {
      path     = "@allThePlugins@",
      fallback = false
    },
  })
else
  return require('lazy').setup(plugins, {})
end
