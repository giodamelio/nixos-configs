-- Use space as the leader key and , as the localleader
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

-- Set the default tab to 2 spaces
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true -- Use spaces instead of tabs

-- Show relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Make search smarter
vim.opt.ignorecase = true -- Case insensitive search
vim.opt.smartcase  = true -- If there are uppercase letters, become case-sensitive

-- Use the system clipboard by default
vim.opt.clipboard = 'unnamedplus'

-- Show trailing spaces as dots
vim.opt.list = true
vim.opt.listchars = 'trail:·,tab:  '

-- Highlight the line the cursor is on
vim.opt.cursorline = true

-- Completely disable the mouse
vim.opt.mouse = ''

-- Options for completions
vim.opt.completeopt = 'menu,menuone,noselect'

-- Enable 24 bit colors requires ISO-8613-3 compatible terminal
vim.opt.termguicolors = true
