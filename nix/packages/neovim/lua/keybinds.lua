local wk = require("which-key")

local tb = require("telescope.builtin")
local neotest = require("neotest")

-- Misc top level bindings
wk.add({
	{ "<leader><Tab>", "<cmd>edit #<cr>", desc = "Switch to last buffer" },
})

-- Fuzzy Finding
wk.add({
	{ "<leader>f", group = "Find" },
	{ "<leader>f?", tb.help_tags, desc = "Find help tags" },
	{ "<leader>fb", tb.buffers, desc = "Find buffer" },
	{ "<leader>ff", tb.find_files, desc = "Find file" },
	{ "<leader>fg", tb.live_grep, desc = "Find line in file" },
	{
		"<leader>fh",
		function()
			tb.find_files({ hidden = true })
		end,
		desc = "Find file (including hidden)",
	},
	{ "<leader>fm", tb.marks, desc = "Find marks" },
	{ "<leader>fr", tb.oldfiles, desc = "Find recent files" },
})

-- Diagnostics and Trouble.nvim
wk.add({
	{ "<leader>d", group = "Diagnostics/Trouble" },
	{ "<leader>dd", "<cmd>TroubleToggle document_diagnostics<cr>", desc = "Trouble document diagnostics" },
	{ "<leader>de", "<cmd>TroubleToggle lsp_definitions<cr>", desc = "Trouble definitions" },
	{ "<leader>di", "<cmd>TroubleToggle lsp_implementations<cr>", desc = "Trouble implementations" },
	{
		"<leader>dn",
		function()
			vim.diagnostic.goto_next()
		end,
		desc = "Go to next diagnostic",
	},
	{
		"<leader>dp",
		function()
			vim.diagnostic.goto_prev()
		end,
		desc = "Go to previous diagnostic",
	},
	{ "<leader>dr", "<cmd>TroubleToggle lsp_references<cr>", desc = "Trouble references" },
	{ "<leader>dt", "<cmd>TroubleToggle<cr>", desc = "Time for trouble" },
})

-- Testing
wk.add({
	{ "<leader>t", group = "Testing" },
	{
		"<leader>tf",
		function()
			neotest.run.run(vim.fn.expand("%"))
		end,
		desc = "Run tests in file",
	},
	{
		"<leader>tp",
		function()
			neotest.output_panel.toggle()
		end,
		desc = "Toggle output panel",
	},
	{
		"<leader>ts",
		function()
			neotest.summary.toggle()
		end,
		desc = "Toggle summary",
	},
	{
		"<leader>tt",
		function()
			neotest.run.run()
		end,
		desc = "Run nearest test",
	},
	{
		"<leader>tw",
		function()
			neotest.watch.toggle(vim.fn.expand("%"))
		end,
		desc = "Watch tests in file",
	},
	{
		"<leader>ta",
		function()
			neotest.run.attach()
		end,
		desc = "Attach to running test",
	},
	{
		"<leader>tl",
		function()
			neotest.run.run_last()
		end,
		desc = "Run last test",
	},
})

-- Language Server
wk.add({
	{ "K", vim.lsp.buf.hover, desc = "Show hover docs" },
	{ "<leader>l", group = "LSP" },
	{ "<leader>lD", vim.lsp.buf.definition, desc = "Show definitions" },
	{ "<leader>ld", vim.lsp.buf.declaration, desc = "Show declarations" },
	{ "<leader>li", vim.lsp.buf.implementation, desc = "Show implementations" },
	{ "<leader>ll", vim.lsp.buf.code_action, desc = "Show code actions" },
	{ "<leader>lr", vim.lsp.buf.references, desc = "Show references" },
	{ "<leader>lt", vim.lsp.buf.type_definition, desc = "Show type definition" },
})

-- Navigate to other files
wk.add({
	{ "<leader>o", group = "Other files" },
	{ "<leader>oc", "<cmd>OtherClear<cr>", desc = "Clear the internal reference to other file" },
	{ "<leader>oo", "<cmd>Other<cr>", desc = "Open the the other file" },
	{ "<leader>os", "<cmd>OtherSplit<cr>", desc = "Open the the other file in a horizontal split" },
	{ "<leader>ov", "<cmd>OtherVSplit<cr>", desc = "Open the the other file in a vertical split" },
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
local gs = require("gitsigns")
local gsa = require("gitsigns.actions")
local gl = require("gitlinker")
-- local gla = require('gitlinker.actions')

wk.add({
	{ "<leader>g", group = "Git" },
	{ "<leader>gg", "<cmd>Neogit<cr>", desc = "Open Neogit UI" },
	{
		"<leader>gb",
		function()
			gs.blame_line(true)
		end,
		desc = "Blame Current Line",
	},
	{
		"<leader>gn",
		function()
			gsa.next_hunk()
		end,
		desc = "Go to next hunk",
	},
	{
		"<leader>gp",
		function()
			gsa.prev_hunk()
		end,
		desc = "Go to previous hunk",
	},
	{
		"<leader>gr",
		function()
			gs.reset_hunk()
		end,
		desc = "Reset hunk",
	},
	{
		"<leader>gs",
		function()
			gs.stage_hunk()
		end,
		desc = "Stage hunk",
	},
	{
		"<leader>gu",
		function()
			gs.undo_stage_hunk()
		end,
		desc = "Unstage hunk",
	},
	{
		"<leader>gy",
		function()
			gl.link({
				-- GitLinker hard codes to the + register which doesn't work over ssh
				-- action = gla.clipboard,
				action = function(url)
					vim.fn.setreg('"', url)
				end,
				lstart = vim.api.nvim_buf_get_mark(0, "<")[1],
				lend = vim.api.nvim_buf_get_mark(0, ">")[1],
			})
		end,
		desc = "Copy permalink to clipboard",
	},
})

wk.add({
	mode = { "v" },
	{ "<leader>g", group = "Git" },
	{
		"<leader>gr",
		function()
			gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end,
		desc = "Reset hunk",
	},
	{
		"<leader>gs",
		function()
			gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end,
		desc = "Stage hunk",
	},
	{
		"<leader>gy",
		function()
			gl.link({
				-- GitLinker hard codes to the + register which doesn't work over ssh
				-- action = gla.clipboard,
				action = function(url)
					vim.fn.setreg('"', url)
				end,
				lstart = vim.api.nvim_buf_get_mark(0, "<")[1],
				lend = vim.api.nvim_buf_get_mark(0, ">")[1],
			})
		end,
		desc = "Copy permalink to clipboard",
	},
})
