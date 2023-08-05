-- Add lazy.nvim from nixpkgs
vim.opt.rtp:prepend('@lazyvim@')

-- Setup basic vim settings
require('basic')

-- Load the plugins
require('plugins')

-- Setup some keybinds
require('keybinds')
