-- Neovim Main configuration file

-- Performance monitoring: Track startup time
local startup_start = vim.uv.hrtime()

-- Load basic settings
require("config.settings")

-- Load key mappings
require("config.keymaps")

-- Load vim-rsi style mappings
require("config.nvim-rsi")

-- Load custom commands
require("config.commands")

-- Load plugin configurations
require("plugins")

-- Report after VimEnter handlers and their scheduled startup work complete.
vim.api.nvim_create_autocmd("VimEnter", {
	group = vim.api.nvim_create_augroup("StartupTiming", { clear = true }),
	once = true,
	callback = function()
		vim.schedule(function()
			local startup_time = (vim.uv.hrtime() - startup_start) / 1000000
			vim.notify(string.format("Neovim startup: %.2fms", startup_time), vim.log.levels.INFO)
		end)
	end,
})
