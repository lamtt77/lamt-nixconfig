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

-- Performance monitoring: Report startup time
local startup_end = vim.uv.hrtime()
local startup_time = (startup_end - startup_start) / 1000000
vim.notify(string.format("Neovim startup: %.2fms", startup_time), vim.log.levels.INFO)
