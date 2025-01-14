-- Trouble
require("trouble").setup()

-- Telescope
local telescope = require("telescope")
local trouble = require("trouble.sources.telescope")

-- Allow opening telescope results in Trouble
telescope.setup({
	defaults = {
		mappings = {
			i = { ["<c-t>"] = trouble.open },
			n = { ["<c-t>"] = trouble.open },
		},
	},
})

-- Snippets
require("luasnip.loaders.from_vscode").lazy_load()

-- Status bar
local lualine = require("lualine")
local default_config = lualine.get_config()

-- Enable lualine
local config = vim.tbl_deep_extend("force", default_config, {
	sections = {
		lualine_c = { "filename", "lsp_progress" },
	},
	winbar = {
		lualine_c = {
			{
				"navic",
				color_correction = nil,
				navic_opts = nil,
			},
		},
	},
	-- Show some help when the tabline is open, I always forget the keys...
	tabline = {
		lualine_a = { { "tabs", mode = 2 } },
		lualine_x = { '"[next tab] gt, [prev tab] gT, [close tab] :tabclose"' },
	},
})
lualine.setup(config)

-- Hide mode display in the command bar since lualine shows it
vim.opt.showmode = false

-- Only show the tabline if there is more then one tab
vim.opt.showtabline = 1

-- Git Status in Gutter
local gs = require("gitsigns")
local gl = require("gitlinker")
local neogit = require("neogit")

gs.setup({
	current_line_blame = true,
})

gl.setup({
	mapping = nil,
})

neogit.setup()

-- ChatGPT
require("chatgpt").setup({
	yank_register = "C",
	chat = {
		keymaps = {
			close = { "<Esc>" },
		},
	},
	edit_with_instructions = {
		diff = false,
		keymaps = {
			close = "<Esc>",
		},
	},
})

-- Oil
require("oil").setup({
	columns = { "icon", "permissions", "size" },
})

-- Open Oil if no file/directory is specified
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if vim.fn.argc() == 0 then
			vim.defer_fn(function()
				require("oil").open()
			end, 10)
		end
	end,
})

-- NeoTest
require("neotest").setup({
	adapters = {
		require("neotest-rust"),
		require("neotest-elixir"),
		require("neotest-go"),
		require("neotest-deno"),
		require("neotest-rspec"),
	},
})

-- Elixir Tools
require("elixir").setup({
	nextls = {
		enable = true,
		cmd = os.getenv("NEXTLS_CMD"),
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
require("other-nvim").setup({
	mappings = {
		"rails",
		"golang",
		-- Elixir + Phoenix Mappings

		-- Go from controller to places
		{
			pattern = "/lib/(.+)_web/controllers/(.+)_controller.ex",
			target = {
				{ context = "test", target = "/test/%1_web/controllers/%2_controller_test.exs" },
			},
		},
		-- Go from controller test to places
		{
			pattern = "/test/(.+)_web/controllers/(.+)_controller_test.exs",
			target = {
				{ context = "controller", target = "/lib/%1_web/controllers/%2_controller.ex" },
			},
		},
		-- Go from context to places
		{
			pattern = "/lib/(.+)/(.+).ex",
			target = {
				{ context = "test", target = "/test/%1/%2_test.exs" },
			},
		},
		-- Go from context test to places
		{
			pattern = "/test/(.+)/(.+)_test.exs",
			target = {
				{ context = "context", target = "/lib/%1/%2.ex" },
			},
		},
	},
})

-- FZF Lua
require("fzf-lua").setup({ "default" })

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

require("nvim-surround").setup()
require("Comment").setup()
require("stay-centered").setup()
