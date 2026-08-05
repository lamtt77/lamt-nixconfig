return {
	-- ─── gitsigns.nvim ───────────────────────────────────────────────────────
	-- Git hunk indicators in the sign column, staging, blame, and text objects.
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "│" },
				change = { text = "─" },
				delete = { text = "╰" },
				topdelete = { text = "╭" },
				changedelete = { text = "┼" },
			},
			-- Show blame virtual text inline (toggle with <leader>hb)
			current_line_blame = false,
			current_line_blame_opts = {
				delay = 500,
				virt_text_pos = "eol",
			},
			on_attach = function(bufnr)
				local gs = require("gitsigns")

				-- Hunk navigation — use nav_hunk (next_hunk/prev_hunk are deprecated)
				vim.keymap.set("n", "]h", function()
					if vim.wo.diff then
						return "]h"
					end
					vim.schedule(function()
						gs.nav_hunk("next")
					end)
					return "<Ignore>"
				end, { expr = true, buffer = bufnr, desc = "Next hunk" })

				vim.keymap.set("n", "[h", function()
					if vim.wo.diff then
						return "[h"
					end
					vim.schedule(function()
						gs.nav_hunk("prev")
					end)
					return "<Ignore>"
				end, { expr = true, buffer = bufnr, desc = "Previous hunk" })

				-- First / last hunk in buffer
				vim.keymap.set("n", "]H", function()
					gs.nav_hunk("last")
				end, { buffer = bufnr, desc = "Last hunk" })
				vim.keymap.set("n", "[H", function()
					gs.nav_hunk("first")
				end, { buffer = bufnr, desc = "First hunk" })

				-- Hunk operations
				vim.keymap.set("n", "<leader>hs", gs.stage_hunk, { buffer = bufnr, desc = "Stage hunk" })
				vim.keymap.set("n", "<leader>hr", gs.reset_hunk, { buffer = bufnr, desc = "Reset hunk" })
				vim.keymap.set("n", "<leader>hS", gs.stage_buffer, { buffer = bufnr, desc = "Stage buffer" })
				vim.keymap.set("n", "<leader>hu", gs.undo_stage_hunk, { buffer = bufnr, desc = "Undo stage hunk" })
				vim.keymap.set("n", "<leader>hR", gs.reset_buffer, { buffer = bufnr, desc = "Reset buffer" })
				vim.keymap.set("n", "<leader>hp", gs.preview_hunk, { buffer = bufnr, desc = "Preview hunk" })
				vim.keymap.set("n", "<leader>hb", function()
					gs.blame_line({ full = true })
				end, { buffer = bufnr, desc = "Blame line (full)" })
				vim.keymap.set("n", "<leader>hB", gs.toggle_current_line_blame, {
					buffer = bufnr,
					desc = "Toggle inline blame",
				})
				-- Diff current file against index
				vim.keymap.set("n", "<leader>hd", gs.diffthis, { buffer = bufnr, desc = "Diff this (index)" })
				vim.keymap.set("n", "<leader>hD", function()
					gs.diffthis("~")
				end, { buffer = bufnr, desc = "Diff this (last commit)" })

				-- Visual-mode range stage / reset
				vim.keymap.set("v", "<leader>hs", function()
					gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, { buffer = bufnr, desc = "Stage selected hunk" })
				vim.keymap.set("v", "<leader>hr", function()
					gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, { buffer = bufnr, desc = "Reset selected hunk" })

				-- Text object: `ih` selects the hunk under cursor in operator-pending / visual
				vim.keymap.set(
					{ "o", "x" },
					"ih",
					":<C-U>Gitsigns select_hunk<CR>",
					{ buffer = bufnr, desc = "Select hunk" }
				)
			end,
		},
	},

	-- ─── diffview.nvim ───────────────────────────────────────────────────────
	-- Full diff viewer and merge tool. Standalone so it can be opened directly
	-- with :DiffviewOpen / :DiffviewFileHistory, and is also used by neogit.
	-- NOTE: listed here as the primary spec; neogit references it only as a
	-- dependency so lazy.nvim will not double-initialise it.
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
		keys = {
			{ "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview: open" },
			{ "<leader>gD", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
			{ "<leader>gF", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
			{ "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: branch history" },
		},
		opts = {
			enhanced_diff_hl = true,
			view = {
				merge_tool = {
					-- diff3_mixed: 3-way merge with base in the centre — best for conflicts
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
		},
	},

	-- ─── neogit ──────────────────────────────────────────────────────────────
	-- Magit-inspired full Git UI.
	-- diffview.nvim is listed as a dependency here so neogit can open diffs
	-- inside diffview, but the full config above is authoritative.
	{
		"NeogitOrg/neogit",
		cmd = "Neogit",
		keys = {
			{ "<leader>gg", "<cmd>Neogit<cr>", desc = "Neogit status" },
			{ "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Neogit commit" },
			{ "<leader>gp", "<cmd>Neogit push<cr>", desc = "Neogit push" },
			{ "<leader>gl", "<cmd>Neogit pull<cr>", desc = "Neogit pull" },
			{ "<leader>gb", "<cmd>Neogit branch<cr>", desc = "Neogit branch" },
		},
		-- Only declare diffview as a dep (no config here — config lives above)
		dependencies = { "sindrets/diffview.nvim" },
		opts = {
			-- filewatcher is unreliable inside NixOS read-only store paths
			filewatcher = { enabled = false },
			graph_style = "unicode",
			integrations = {
				diffview = true,
				telescope = true,
				fzf_lua = false,
			},
			signs = {
				section = { "▶", "▼" },
				item = { "▶", "▼" },
				hunk = { "", "" },
			},
			mappings = {
				status = {
					-- Stage/unstage with familiar shortcuts inside Neogit status buffer
					["<C-s>"] = "Stage",
					["<C-u>"] = "Unstage",
					["<C-r>"] = "RefreshBuffer",
				},
			},
		},
	},
}
