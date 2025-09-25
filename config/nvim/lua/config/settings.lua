-- Basic Neovim settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.termguicolors = true

-- disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.o.sessionoptions="blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

-- Window split settings
vim.opt.splitright = false  -- Open vertical splits on the left
vim.opt.splitbelow = false  -- Open horizontal splits above

-- Theme settings
vim.opt.background = "dark" -- or "light" for light mode

-- Swap file settings
vim.opt.directory = vim.fn.stdpath('data') .. '/swap//'
vim.opt.swapfile = true

-- Undo settings
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath('data') .. '/undo//'
vim.opt.undolevels = 10000
vim.opt.undoreload = 10000

-- Create undo directory if it doesn't exist
local undo_dir = vim.fn.stdpath('data') .. '/undo'
if vim.fn.isdirectory(undo_dir) == 0 then
  vim.fn.mkdir(undo_dir, 'p')
end

-- Completion settings
vim.opt.completeopt = {'menu', 'menuone', 'noselect'}
-- Enable wildmenu for better command line completion
vim.opt.wildmenu = true
vim.opt.wildmode = 'list:longest'

-- Timeout settings for better key mapping recognition
-- vim.opt.timeoutlen = 1000  -- Default time to wait for mapped sequence to complete
vim.opt.ttimeoutlen = 100  -- Time to wait for key code sequence to complete

-- Spell checking configuration
vim.opt.spelllang = 'en_us'             -- Set language to US English
vim.opt.spellfile = vim.fn.stdpath('config') .. '/spell/en.utf-8.add'  -- Custom dictionary file