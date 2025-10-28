return {
	-- Fuzzy finder
	{
		"nvim-telescope/telescope.nvim",
		lazy = true,
		dependencies = { "nvim-lua/plenary.nvim" },
		keys = {
			{
				"<leader><Space>",
				function()
					local telescope_builtin = require("telescope.builtin")
					local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
					if git_root ~= "" then
						telescope_builtin.git_files()
					else
						telescope_builtin.find_files()
					end
				end,
				desc = "Find files (git-aware)",
			},
			{
				"<leader>.",
				function()
					require("telescope.builtin").find_files({ hidden = true })
				end,
				desc = "Find files current folder",
			},
			{
				"<leader>ff",
				function()
					local telescope_builtin = require("telescope.builtin")
					local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
					local cwd = git_root ~= "" and git_root or vim.fn.getcwd()
					telescope_builtin.find_files({ cwd = cwd, hidden = true })
				end,
				desc = "Find all files in project root (including hidden/untracked)",
			},
			{
				"<leader>/",
				function()
					local telescope_builtin = require("telescope.builtin")
					local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
					local cwd = git_root ~= "" and git_root or vim.fn.getcwd()
					telescope_builtin.live_grep({ cwd = cwd, additional_args = { "--hidden" } })
				end,
				desc = "Live grep from project root",
			},
			{
				"<leader>'",
				function()
					require("telescope.builtin").resume()
				end,
				desc = "Resume last search",
			},
			{
				"<leader>fg",
				function()
					require("telescope.builtin").grep_string({ additional_args = { "--hidden" } })
				end,
				desc = "Grep string (including hidden)",
			},
			{
				"<leader>fr",
				function()
					require("telescope.builtin").oldfiles()
				end,
				desc = "Recent files",
			},
			{
				"<leader>bb",
				function()
					require("telescope.builtin").buffers()
				end,
				desc = "Find buffers",
			},
			{
				"<leader>H",
				function()
					require("telescope.builtin").help_tags()
				end,
				desc = "Help tags",
			},
			{
				"<leader>M",
				function()
					require("telescope.builtin").man_pages()
				end,
				desc = "Man pages",
			},
			{
				"<leader>fc",
				function()
					require("telescope.builtin").command_history()
				end,
				desc = "Command history",
			},
			{
				"<leader>f/",
				function()
					require("telescope.builtin").search_history()
				end,
				desc = "Search history",
			},
			{
				"<leader>fR",
				function()
					require("telescope.builtin").registers()
				end,
				desc = "Registers",
			},
			{
				"<leader>fk",
				function()
					require("telescope.builtin").keymaps()
				end,
				desc = "Keymaps",
			},
			{
				"<leader>fd",
				function()
					require("telescope.builtin").diagnostics()
				end,
				desc = "Diagnostics",
			},
			{
				"<leader>fs",
				function()
					require("telescope.builtin").lsp_document_symbols()
				end,
				desc = "Document symbols",
			},
			{
				"<leader>fS",
				function()
					require("telescope.builtin").lsp_workspace_symbols()
				end,
				desc = "Workspace symbols",
			},
			{
				"<leader>fi",
				function()
					require("telescope.builtin").lsp_implementations()
				end,
				desc = "Implementations",
			},
			{
				"<leader>ft",
				function()
					require("telescope.builtin").lsp_type_definitions()
				end,
				desc = "Type definitions",
			},
			{
				"<leader>gf",
				function()
					require("telescope.builtin").git_files()
				end,
				desc = "Git files",
			},
			{
				"<leader>gc",
				function()
					require("telescope.builtin").git_commits()
				end,
				desc = "Git commits",
			},
			{
				"<leader>gC",
				function()
					require("telescope.builtin").git_bcommits()
				end,
				desc = "Git buffer commits",
			},
			{
				"<leader>gb",
				function()
					require("telescope.builtin").git_branches()
				end,
				desc = "Git branches",
			},
			{
				"<leader>fq",
				function()
					require("telescope.builtin").quickfix()
				end,
				desc = "Quickfix list",
			},
			{
				"<leader>fl",
				function()
					require("telescope.builtin").loclist()
				end,
				desc = "Location list",
			},
			{
				"<leader>sb",
				"<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>",
				desc = "Search in current buffer",
			},
		},
		config = function()
			local telescope = require("telescope")
			telescope.setup({
				defaults = {
					file_ignore_patterns = { "node_modules/" },
					mappings = {
						i = {
							["<M-n>"] = require("telescope.actions").cycle_history_next,
							["<M-p>"] = require("telescope.actions").cycle_history_prev,
						},
					},
				},
				pickers = {
					find_files = {
						hidden = false,
					},
				},
			})
		end,
	},
}
