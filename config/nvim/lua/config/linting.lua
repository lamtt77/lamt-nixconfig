-- Linting configuration
return {
	-- nvim-lint for linting
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local lint = require("lint")

			lint.linters_by_ft = {
				lua = { "luacheck" },
				python = { "ruff" },
				javascript = { "eslint" },
				typescript = { "eslint" },
				nix = { "statix" },
				c = { "cppcheck" },
				cpp = { "cppcheck" },
				rust = { "clippy" },
				go = { "golangci_lint" },
			}

			-- Create autocommand to trigger linting
			local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = lint_augroup,
				callback = function()
					lint.try_lint()
				end,
			})

			-- Keymap for manual linting
			vim.keymap.set("n", "<leader>ml", function()
				lint.try_lint()
			end, { desc = "Trigger linting for current file" })
		end,
	},
}
