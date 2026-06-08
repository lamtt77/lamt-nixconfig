-- LSP Configuration
local function get_capabilities()
	local capabilities = vim.lsp.protocol.make_client_capabilities()
	return require("blink.cmp").get_lsp_capabilities(capabilities)
end

return {
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		version = "*",
		config = function()
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
			local capabilities = get_capabilities()
			-- Disable dynamic file watching to prevent high CPU load on macOS
			if capabilities.workspace then
				capabilities.workspace.didChangeWatchedFiles = {
					dynamicRegistration = false,
				}
			end

			-- LspAttach autocommand for buffer-local keybindings
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
				callback = function(ev)
					local bufopts = { noremap = true, silent = true, buffer = ev.buf }

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
				end,
			})

			-- Server configurations
			local servers = {
				lua_ls = {
					capabilities = capabilities,
					settings = {
						Lua = {
							runtime = { version = "LuaJIT" },
							diagnostics = { globals = { "vim" } },
							-- Narrow to just the Neovim stdlib; indexing all runtime files
							-- (nvim_get_runtime_file("", true)) is very expensive on attach.
							workspace = {
								library = { vim.fn.expand("$VIMRUNTIME/lua") },
								checkThirdParty = false,
							},
							telemetry = { enable = false },
						},
					},
				},
				ts_ls = {
					capabilities = capabilities,
				},
				gopls = {
					capabilities = capabilities,
				},
				pyright = {
					capabilities = capabilities,
				},
				nil_ls = {
					capabilities = capabilities,
					settings = {
						["nil"] = {
							-- autoArchive runs `nix flake archive` on open, which blocks
							-- for seconds while it fetches flake inputs over the network.
							nix = { autoArchive = false },
						},
					},
				},
				clangd = {
					capabilities = capabilities,
				},
			}

			-- Setup each server
			for server, config in pairs(servers) do
				vim.lsp.config(server, config)
				vim.lsp.enable(server)
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
		event = { "BufReadPre", "BufNewFile" },
		cmd = { "TSUpdate", "TSInstall", "TSConfigInfo" },
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter.configs").setup({
				ensure_installed = { "lua", "vim", "vimdoc", "python", "javascript", "typescript", "nix", "rust" },
				highlight = {
					enable = true,
					-- Disable legacy VimL syntax when Treesitter is active.
					-- syntax/rust.vim (and others) run a full regex sync pass that
					-- showed as the #1 profiler offender (~100 s overflow) when
					-- opening Rust files from Neogit.
					disable = function(_, buf)
						-- Only disable for large files where regex is slowest
						local max_lines = 5000
						local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
						if ok and stats and stats.size > 1024 * 1024 then
							return true -- also bail on files > 1 MB
						end
						local line_count = vim.api.nvim_buf_line_count(buf)
						return line_count > max_lines
					end,
					-- After TS attaches, turn off the VimL :syntax engine so both
					-- don't run at the same time on the same buffer.
					additional_vim_regex_highlighting = false,
				},
				indent = { enable = true },
				modules = {},
				sync_install = false,
				ignore_install = {},
				auto_install = false,
			})

			-- Retain Vim syntax as a fallback, but stop it once Treesitter has
			-- successfully attached to avoid running both highlighters.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("TreesitterSyntaxFallback", { clear = true }),
				callback = function(args)
					local buf = args.buf
					if vim.treesitter.highlighter.active[buf] then
						vim.bo[buf].syntax = ""
					end
				end,
			})
		end,
	},

	-- Rust tools (LSP successor)
	{
		"mrcjkb/rustaceanvim",
		version = "^9",
		ft = "rust",
		config = function()
			local capabilities = get_capabilities()
			vim.g.rustaceanvim = {
				server = {
					on_attach = function(_, bufnr)
						-- Hover actions
						vim.keymap.set("n", "<C-space>", function()
							vim.cmd.RustLsp("hover", "actions")
						end, { buffer = bufnr, desc = "Rust hover actions" })
						-- Code action groups
						vim.keymap.set("n", "<Leader>a", function()
							vim.cmd.RustLsp("codeAction")
						end, { buffer = bufnr, desc = "Rust code action" })
					end,
					capabilities = capabilities,
					settings = {
						["rust-analyzer"] = {
							files = {
								excludeDirs = {
									"target",
									"apps/installer-rs/target",
									".git",
									".direnv",
									".devenv",
									"_tmp",
									".cargo",
								},
							},
							checkOnSave = true,
							check = {
								command = "check",
							},
						},
					},
				},
			}
		end,
	},
}
