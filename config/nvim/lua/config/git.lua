return {
	-- Git signs and hunk management
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("gitsigns").setup({
				signs = {
					add = { text = "│" },
					change = { text = "─" },
					delete = { text = "╰" },
					topdelete = { text = "╭" },
					changedelete = { text = "┼" },
				},
				on_attach = function(bufnr)
					local gs = require("gitsigns")

					-- Hunk navigation
					vim.keymap.set("n", "]h", function()
						if vim.wo.diff then
							return "]h"
						end
						vim.schedule(function()
							gs.next_hunk()
						end)
						return "<Ignore>"
					end, { expr = true, buffer = bufnr, desc = "Next hunk" })

					vim.keymap.set("n", "[h", function()
						if vim.wo.diff then
							return "[h"
						end
						vim.schedule(function()
							gs.prev_hunk()
						end)
						return "<Ignore>"
					end, { expr = true, buffer = bufnr, desc = "Previous hunk" })

					-- Hunk operations
					vim.keymap.set("n", "<leader>hs", gs.stage_hunk, { buffer = bufnr, desc = "Stage hunk" })
					vim.keymap.set("n", "<leader>hr", gs.reset_hunk, { buffer = bufnr, desc = "Reset hunk" })
					vim.keymap.set("n", "<leader>hp", gs.preview_hunk, { buffer = bufnr, desc = "Preview hunk" })
					vim.keymap.set("n", "<leader>hb", function()
						gs.blame_line({ full = true })
					end, { buffer = bufnr, desc = "Blame line" })

					-- Text object
					vim.keymap.set(
						{ "o", "x" },
						"ih",
						":<C-U>Gitsigns select_hunk<CR>",
						{ buffer = bufnr, desc = "Select hunk" }
					)
				end,
			})
		end,
	},

	-- Modern Git interface (Magit-inspired)
	{
		"NeogitOrg/neogit",
		cmd = "Neogit",
		keys = {
			{ "<leader>gg", "<cmd>Neogit<CR>", desc = "Neogit status" },
		},
		dependencies = { "sindrets/diffview.nvim" },
		config = function()
			require("neogit").setup({
				filewatcher = {
					enabled = false,
				},
				integrations = {
					diffview = true,
					fzf_lua = false,
					telescope = true,
				},
				graph_style = "unicode",
				signs = {
					section = { "▶", "▼" },
					item = { "▶", "▼" },
					hunk = { "", "" },
				},
				mappings = {
					status = {
						["<C-s>"] = "Stage",
						["<C-u>"] = "Unstage",
					},
				},
			})
		end,
	},

	-- Enhanced diff viewing
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
		config = function()
			require("diffview").setup({
				enhanced_diff_hl = true,
				view = {
					merge_tool = {
						layout = "diff3_mixed",
					},
				},
				file_panel = {
					listing_style = "tree",
					tree_options = {
						flatten_dirs = true,
						folder_statuses = "only_folded",
					},
				},
			})
		end,
	},
}
