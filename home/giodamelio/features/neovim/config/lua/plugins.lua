-- Set the Lazy.nvim lockfile path to a special location if we are on NixOS
local lazy_lockfile_path
if vim.fn.isdirectory(vim.fn.expand("~/nixos-configs")) then
  lazy_lockfile_path = "~/nixos-configs/home/giodamelio/features/neovim/config/lazy-lock.json"
else
  -- Lazy.nvim default
  lazy_lockfile_path = vim.fn.stdpath("config") .. "/lazy-lock.json"
end


return require('lazy').setup({
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

      vim.cmd[[colorscheme tokyonight]]
    end
  },

  -- Interactivly show keybindings
  {
    'folke/which-key.nvim',
    config = function()
      require('which-key').setup {}
    end
  },

  -- Fuzzy find all the things
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local wk = require("which-key")
      local builtin = require('telescope.builtin')
      wk.register({
          f = {
            name = "file",
            f = { builtin.find_files, "Find File" },
            g = { builtin.live_grep, "Live Grep" }
          },
        },
        { prefix = "<leader>" }
      )
    end
  }
}, {
  lockfile = lazy_lockfile_path
})
