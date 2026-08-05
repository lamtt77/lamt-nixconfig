return {
	-- Blink completion engine
	{
		"saghen/blink.cmp",
		dependencies = {
			"rafamadriz/friendly-snippets",
		},
		version = "*",
		config = function()
			local blink = require("blink.cmp")

			blink.setup({
				snippets = {
					preset = "default",
				},
				keymap = {
					preset = "default",
					["<CR>"] = { "select_and_accept", "fallback" },
				},
				appearance = {
					use_nvim_cmp_as_default = false,
					nerd_font_variant = "mono",
				},
				sources = {
					default = { "lsp", "path", "snippets", "buffer", "copilot" },
					providers = {
						copilot = {
							name = "copilot",
							module = "blink-cmp-copilot",
							async = true,
						},
						dictionary = {
							module = "blink-cmp-dictionary",
							name = "Dict",
							min_keyword_length = 3,
							opts = {
								dictionary_files = { "/usr/share/dict/words" },
							},
						},
					},
				},
				completion = {
					menu = {
						border = "rounded",
						winhighlight = "Normal:Pmenu,FloatBorder:Pmenu,CursorLine:PmenuSel,Search:None",
						draw = {
							columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "source_name" } },
						},
					},
					documentation = {
						window = { border = "rounded" },
						auto_show = true,
						auto_show_delay_ms = 500,
					},
					ghost_text = { enabled = true },
				},
				signature = { enabled = true },
			})

			-- Manual dictionary completion trigger
			vim.keymap.set("i", "<A-d>", function()
				require("blink.cmp").show({ providers = { "dictionary" } })
			end, { desc = "Trigger dictionary completion" })
		end,
	},

	-- Blink Copilot integration
	{
		"giuxtaposition/blink-cmp-copilot",
	},

	-- Blink Dictionary source
	{
		"Kaiser-Yang/blink-cmp-dictionary",
	},

	-- Keymap hints (which-key)
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			preset = "classic",
			delay = 300,
			spec = {
				{ "<leader>1", desc = "H1 Heading" },
				{ "<leader>2", desc = "H2 Heading" },
				{ "<leader>3", desc = "H3 Heading" },
				{ "<leader>4", desc = "H4 Heading" },
				{ "<leader>5", desc = "H5 Heading" },
				{ "<leader>a", group = "AI/Avante" },
				{ "<leader>b", group = "Buffer" },
				{ "<leader>c", group = "Code / Directory" },
				{ "<leader>d", group = "Debug/DAP" },
				{ "<leader>e", desc = "Mini Files (cwd)" },
				{ "<leader>E", desc = "Toggle Neo-tree" },
				{ "<leader>f", group = "Find/Files" },
				{ "<leader>fy", desc = "Yank filename" },
				{ "<leader>fY", desc = "Yank full path" },
				{ "<leader>g", group = "Git" },
				{ "<leader>h", group = "Git Hunks" },
				{ "<leader>i", group = "Screenshot/Images" },
				{ "<leader>l", group = "LSP" },
				{ "<leader>m", group = "Media/Formatting" },
				{ "<leader>o", group = "AI/Opencode" },
				{ "<leader>p", desc = "Yank history" },
				{ "<leader>q", group = "Quit" },
				{ "<leader>R", desc = "Restart Neovim" },
				{ "<leader>s", group = "Search/Spell" },
				{ "<leader>t", group = "Theme/Toggles/Treesitter" },
				{ "<leader>w", group = "Workspace" },
				{ "<leader>z", desc = "Undo" },
				{ "<leader>Z", desc = "Redo" },
				{ "<leader>`", desc = "Alternate buffer" },
			},
		},
	},
}
