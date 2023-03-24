-- Boostrap Lazy.nvim package manager
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Setup basic vim settings
require('basic')

-- Load all the plugins
require('plugins')

-- Hack to get the path from the treesitter grammers into the Neovim runtimepath
local treesitter_path = vim.fn.readfile(vim.fn.expand('~/.config/nvim-treesitter-runtimepath-hack.txt'))
vim.opt.runtimepath:append(treesitter_path)
