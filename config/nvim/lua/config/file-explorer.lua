return {
	-- File explorer
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-tree/nvim-web-devicons", -- optional, but recommended
		},
		config = function()
			require("neo-tree").setup({
				filesystem = {
					hijack_netrw_behavior = "disabled",
					filtered_items = {
						hide_by_name = { -- Hide specific files/patterns
							".git",
							".DS_Store",
							"node_modules",
						},
					},
					follow_current_file = { enabled = true }, -- Focus on current file
					use_libuv_file_watcher = true, -- Better performance
				},
				window = {
					mappings = {
						["H"] = "toggle_hidden", -- Toggle hidden files with H key
					},
				},
				default_component_configs = {
					git_status = {
						symbols = {
							added = "✚",
							modified = "✹",
							deleted = "✖",
							renamed = "➜",
							untracked = "★",
							ignored = "◌",
							unstaged = "✗",
							staged = "✓",
							conflict = "",
						},
					},
				},
			})
		end,
		lazy = true, -- Allow Neo-tree to handle its own lazy loading
		keys = {
			{ "<leader>E", ":Neotree filesystem toggle<CR>", desc = "Toggle Neo-tree" },
		},
	},
}
