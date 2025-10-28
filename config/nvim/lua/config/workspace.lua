return {
	-- Neovim Project Manager - load after VimEnter to avoid startup conflicts
	{
		"coffebar/neovim-project",
		lazy = true,
		event = "VimEnter", -- Load after startup is complete
		config = function()
			require("neovim-project").setup({
				projects = {
					"~/lamt-nixconfig/",
					"~/lab/*",
					"~/lab/nix-other/*",
					"~/work/*",
				},
				last_session_on_startup = false, -- Disable automatic session loading
			})

			vim.opt.sessionoptions:append("globals")
		end,
		dependencies = {
			{ "nvim-lua/plenary.nvim" },
			{ "nvim-telescope/telescope.nvim" },
		},
		keys = {
			{ "<leader>ww", "<cmd>NeovimProjectHistory<CR>", desc = "Find recent projects" },
			{ "<leader>wd", "<cmd>NeovimProjectDiscover<CR>", desc = "Discover projects" },
			{ "<leader>wr", "<cmd>NeovimProjectDiscover history<CR>", desc = "Find projects by history" },
			{ "<leader>wl", "<cmd>NeovimProjectLoadRecent<CR>", desc = "Load recent project" },
		},
	},
	{
		"Shatur/neovim-session-manager",
		lazy = false, -- Load on startup
		config = function()
			-- Enable autoread to automatically reload files changed outside Vim
			vim.o.autoread = true
			-- Suppress ATTENTION messages for swap files
			vim.o.shortmess = vim.o.shortmess .. 'A'

			require("session_manager").setup({
				autoload_mode = require('session_manager.config').AutoloadMode.LastSession,
				autosave_last_session = true,
				autosave_ignore_dirs = {
					vim.fn.expand("~"),
					"/tmp",
				},
				autosave_ignore_filetypes = {
					"ccc-ui",
					"gitcommit",
					"gitrebase",
					"qf",
					"toggleterm",
				},
			})
		end,
	},
}
