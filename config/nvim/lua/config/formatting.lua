-- Formatting configuration
return {
	-- Conform for formatting
	{
		"stevearc/conform.nvim",
		event = "VeryLazy",
		init = function()
			-- Global flag: set to false to disable format-on-save session-wide.
			-- Toggle with <leader>uf.
			vim.g.autoformat = false
		end,
		config = function()
			local conform = require("conform")

			conform.setup({
				formatters_by_ft = {
					lua = { "stylua" },
					python = { "ruff_format" },
					javascript = { "prettier" },
					typescript = { "prettier" },
					javascriptreact = { "prettier" },
					typescriptreact = { "prettier" },
					json = { "prettier" },
					yaml = { "prettier" },
					markdown = { "prettier" },
					nix = { "nixfmt" },
					c = { "clang_format" },
					cpp = { "clang_format" },
					rust = { "rustfmt" },
					go = { "gofmt" },
				},
				format_on_save = function(_bufnr)
					if not vim.g.autoformat then
						return
					end
					return { lsp_fallback = true }
				end,
			})

			-- Manual format: <leader>lf
			vim.keymap.set({ "n", "v" }, "<leader>lf", function()
				conform.format({ lsp_fallback = true, async = false, timeout_ms = 1000 })
			end, { desc = "Format file or range" })

			-- Toggle format-on-save (<leader>tf)
			vim.keymap.set("n", "<leader>tf", function()
				vim.g.autoformat = not vim.g.autoformat
				local state = vim.g.autoformat and "enabled" or "disabled"
				vim.notify("Format-on-save " .. state, vim.log.levels.INFO)
			end, { desc = "Toggle format-on-save" })
		end,
	},
}
