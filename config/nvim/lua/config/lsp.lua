-- LSP Configuration
return {
	{
		"neovim/nvim-lspconfig",
		version = "*",
		config = function()
			local lspconfig = require("lspconfig")

			-- Diagnostic configuration
			vim.diagnostic.config({
				virtual_text = true,
				signs = true,
				underline = true,
				update_in_insert = false,
				severity_sort = true,
			})

			-- Diagnostic signs
			vim.diagnostic.config({
				signs = {
					text = {
						[vim.diagnostic.severity.ERROR] = "❌",
						[vim.diagnostic.severity.WARN] = "⚠️",
						[vim.diagnostic.severity.HINT] = "💡",
						[vim.diagnostic.severity.INFO] = "ℹ️",
					},
				},
			})

			-- Setup capabilities
			local capabilities = vim.lsp.protocol.make_client_capabilities()
			capabilities = require("blink.cmp").get_lsp_capabilities(capabilities)

			-- on_attach function for buffer-local keybindings
			local on_attach = function(client, bufnr)
				local bufopts = { noremap = true, silent = true, buffer = bufnr }

				-- LSP keybindings (buffer-local)
				vim.keymap.set(
					"n",
					"gD",
					vim.lsp.buf.declaration,
					vim.tbl_extend("force", bufopts, { desc = "Go to declaration" })
				)
				vim.keymap.set(
					"n",
					"gd",
					vim.lsp.buf.definition,
					vim.tbl_extend("force", bufopts, { desc = "Go to definition" })
				)
				vim.keymap.set(
					"n",
					"K",
					vim.lsp.buf.hover,
					vim.tbl_extend("force", bufopts, { desc = "Hover documentation" })
				)
				vim.keymap.set(
					"n",
					"gi",
					vim.lsp.buf.implementation,
					vim.tbl_extend("force", bufopts, { desc = "Go to implementation" })
				)
				vim.keymap.set(
					"n",
					"<C-k>",
					vim.lsp.buf.signature_help,
					vim.tbl_extend("force", bufopts, { desc = "Signature help" })
				)
				vim.keymap.set(
					"n",
					"<leader>D",
					vim.lsp.buf.type_definition,
					vim.tbl_extend("force", bufopts, { desc = "Go to type definition" })
				)
				vim.keymap.set(
					"n",
					"<leader>rn",
					vim.lsp.buf.rename,
					vim.tbl_extend("force", bufopts, { desc = "Rename symbol" })
				)
				vim.keymap.set(
					"n",
					"<leader>ca",
					vim.lsp.buf.code_action,
					vim.tbl_extend("force", bufopts, { desc = "Code actions" })
				)
				vim.keymap.set(
					"n",
					"<leader>lr",
					vim.lsp.buf.references,
					vim.tbl_extend("force", bufopts, { desc = "Find references" })
				)
				vim.keymap.set("n", "<leader>fmt", function()
					vim.lsp.buf.format({ async = true })
				end, vim.tbl_extend("force", bufopts, { desc = "Format buffer" }))
			end

			-- Server configurations
			local servers = {
				lua_ls = {
					on_attach = on_attach,
					capabilities = capabilities,
					settings = {
						Lua = {
							runtime = { version = "LuaJIT" },
							diagnostics = { globals = { "vim" } },
							workspace = { library = vim.api.nvim_get_runtime_file("", true) },
							telemetry = { enable = false },
						},
					},
				},
				ts_ls = {
					on_attach = on_attach,
					capabilities = capabilities,
				},
				gopls = {
					on_attach = on_attach,
					capabilities = capabilities,
				},
				pyright = {
					on_attach = on_attach,
					capabilities = capabilities,
				},
				nil_ls = {
					on_attach = on_attach,
					capabilities = capabilities,
					settings = {
						["nil"] = {
							formatting = { command = { "alejandra" } },
							nix = { autoArchive = true },
						},
					},
				},
				clangd = {
					on_attach = on_attach,
					capabilities = capabilities,
				},
			}

			-- Setup each server
			for server, config in pairs(servers) do
				lspconfig[server].setup(config)
			end
		end,
		keys = {
			{
				"<leader>ld",
				function()
					if vim.diagnostic.is_enabled() then
						vim.diagnostic.enable(false)
						vim.notify("Diagnostics disabled", vim.log.levels.INFO)
					else
						vim.diagnostic.enable(true)
						vim.notify("Diagnostics enabled", vim.log.levels.INFO)
					end
				end,
				desc = "Toggle diagnostics",
			},
		},
	},

	-- Treesitter
	{
		"nvim-treesitter/nvim-treesitter",
		event = "BufReadPre",
		cmd = { "TSUpdate", "TSInstall", "TSConfigInfo" },
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter.configs").setup({
				ensure_installed = { "lua", "vim", "vimdoc", "python", "javascript", "typescript", "nix" },
				highlight = { enable = true },
				indent = { enable = true },
				modules = {},
				sync_install = false,
				ignore_install = {},
				auto_install = false,
			})
		end,
	},

	-- Rust tools (LSP)
	{
		"simrat39/rust-tools.nvim",
		config = function()
			local rt = require("rust-tools")
			rt.setup({
				server = {
					on_attach = function(_, bufnr)
						-- Hover actions
						vim.keymap.set(
							"n",
							"<C-space>",
							rt.hover_actions.hover_actions,
							{ buffer = bufnr, desc = "Rust hover actions" }
						)
						-- Code action groups
						vim.keymap.set(
							"n",
							"<Leader>a",
							rt.code_action_group.code_action_group,
							{ buffer = bufnr, desc = "Rust code action groups" }
						)
					end,
				},
				-- Disable rust-tools DAP adapter to avoid conflicts with mason codelldb
				dap = {
					adapter = false,
				},
			})
		end,
	},
}
