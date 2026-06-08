return {
	-- Search and replace (wgrep-like)
	{
		"MagicDuck/grug-far.nvim",
		cmd = "GrugFar",
		keys = {
			{
				"<leader>S",
				function()
					require("grug-far").open()
				end,
				desc = "Open GrugFar search/replace",
			},
			{
				"<leader>sw",
				function()
					require("grug-far").open({
						prefills = { search = vim.fn.expand("<cword>") },
					})
				end,
				desc = "Search current word with GrugFar",
			},
			{
				"<leader>s",
				function()
					require("grug-far").with_visual_selection()
				end,
				mode = "v",
				desc = "Search current selection with GrugFar",
			},
		},
		config = function()
			require("grug-far").setup({
				-- Minimal setup, defaults are excellent
			})
		end,
	},
}
