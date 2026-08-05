return {
	-- Modern Undo tree in pure Lua
	{
		"jiaoshijie/undotree",
		dependencies = "nvim-lua/plenary.nvim",
		config = true,
		keys = {
			{
				"<leader>tu",
				function()
					require("undotree").toggle()
				end,
				desc = "Toggle undo tree",
			},
		},
	},
}