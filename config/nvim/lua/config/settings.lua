-- Basic Neovim settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.termguicolors = true
vim.opt.autoread = true
vim.opt.updatetime = 300

-- System clipboard: auto-disable in SSH sessions so OSC-52 can handle it
vim.opt.clipboard = vim.env.SSH_CONNECTION and '' or 'unnamedplus'

-- Confirm before quitting unsaved buffers (prevents accidental data loss)
vim.opt.confirm = true

-- Keep N lines visible above/below cursor while scrolling
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Highlight the current line
vim.opt.cursorline = true

-- Show effects of :substitute and similar commands live in a split
vim.opt.inccommand = 'nosplit'

-- Show some invisible chars (tabs and trailing spaces)
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Max items shown in the popup-menu (0 = all)
vim.opt.pumheight = 10

-- Hide * markup for bold/italic in markdown (renders visually)
vim.opt.conceallevel = 2

-- Use ripgrep when available (much faster :grep / :vimgrep)
if vim.fn.executable('rg') == 1 then
	vim.opt.grepprg = 'rg --vimgrep --smart-case'
	vim.opt.grepformat = '%f:%l:%c:%m'
end

-- Keep window layout stable when splitting
vim.opt.splitkeep = 'screen'

-- Keep legacy syntax available for filetypes without a Treesitter parser.
-- The Treesitter setup disables it per buffer after its highlighter attaches.
vim.cmd("syntax enable")

-- Cap legacy VimL syntax column to prevent regex engine from scanning long
-- lines before Treesitter attaches or in buffers that use syntax fallback.
vim.opt.synmaxcol = 256

-- disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Persist the visible workspace, not hidden cross-project buffers or terminals.
-- Restoring those buffers eagerly triggers avoidable filetype, LSP, and plugin work.
vim.o.sessionoptions = "blank,curdir,folds,tabpages,winsize,winpos,localoptions"

-- Window split settings
vim.opt.splitright = false -- Open vertical splits on the left
vim.opt.splitbelow = false -- Open horizontal splits above

-- Theme settings
vim.opt.background = "dark" -- or "light" for light mode

-- Swap file settings
vim.opt.directory = vim.fn.stdpath("data") .. "/swap//"
vim.opt.swapfile = true

-- Undo settings
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath("data") .. "/undo//"
vim.opt.undolevels = 10000
vim.opt.undoreload = 10000

-- Create undo directory if it doesn't exist
local undo_dir = vim.fn.stdpath("data") .. "/undo"
if vim.fn.isdirectory(undo_dir) == 0 then
	vim.fn.mkdir(undo_dir, "p")
end

-- Completion settings
vim.opt.completeopt = { "menu", "menuone", "noselect" }
-- Enable wildmenu for better command line completion
vim.opt.wildmenu = true
vim.opt.wildmode = "list:longest"

-- Timeout settings for better key mapping recognition
-- vim.opt.timeoutlen = 1000  -- Default time to wait for mapped sequence to complete
vim.opt.ttimeoutlen = 100 -- Time to wait for key code sequence to complete

-- Spell checking configuration
vim.opt.spelllang = "en_us" -- Set language to US English
vim.opt.spellfile = vim.fn.stdpath("config") .. "/spell/en.utf-8.add" -- Custom dictionary file

-- FIXME: Workaround for Neovim 0.12 treesitter table issue
-- In some cases, captures return a list of nodes instead of a single node,
-- causing 'range' method errors in get_node_text and get_range.
local ts = vim.treesitter
if ts and ts.get_node_text then
	local old_get_node_text = ts.get_node_text
	ts.get_node_text = function(node, source, opts)
		if type(node) == "table" and node[1] and type(node[1]) == "userdata" then
			node = node[1]
		end
		return old_get_node_text(node, source, opts)
	end
end
if ts and ts.get_range then
	local old_get_range = ts.get_range
	ts.get_range = function(node, bufnr, metadata)
		if type(node) == "table" and node[1] and type(node[1]) == "userdata" then
			node = node[1]
		end
		return old_get_range(node, bufnr, metadata)
	end
end
