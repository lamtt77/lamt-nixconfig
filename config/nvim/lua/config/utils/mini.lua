return {
	-- Mini.nvim ecosystem
	{
		"nvim-mini/mini.nvim",
		config = function()
			-- File operations (replace oil)
			require("mini.files").setup({
				options = {
					use_as_default_explorer = true,
				},
				windows = {
					preview = true,
					width_preview = 50,
				},
			})

			-- Ranger-style navigation mappings
			vim.api.nvim_create_autocmd("User", {
				pattern = "MiniFilesBufferCreate",
				callback = function(args)
					vim.keymap.set("n", "gh", function()
						MiniFiles.open(vim.fn.expand("~"))
					end, { buffer = args.data.buf_id, desc = "Go to home directory" })
					vim.keymap.set("n", "g/", function()
						MiniFiles.open("/")
					end, { buffer = args.data.buf_id, desc = "Go to root directory" })
					vim.keymap.set("n", "ge", function()
						MiniFiles.open("/etc")
					end, { buffer = args.data.buf_id, desc = "Go to /etc directory" })
					vim.keymap.set("n", "gu", function()
						MiniFiles.open("/usr")
					end, { buffer = args.data.buf_id, desc = "Go to /usr directory" })
					vim.keymap.set("n", "gv", function()
						MiniFiles.open("/var")
					end, { buffer = args.data.buf_id, desc = "Go to /var directory" })
					vim.keymap.set("n", "go", function()
						MiniFiles.open("/opt")
					end, { buffer = args.data.buf_id, desc = "Go to /opt directory" })
					vim.keymap.set("n", "<C-f>", function()
						require("mini.pick").builtin.files({ tool = "git" })
					end, { buffer = args.data.buf_id, desc = "Fuzzy file search in project root" })
					vim.keymap.set("n", "<C-y>", function()
						local entry = MiniFiles.get_fs_entry()
						vim.fn.setreg("+", entry.path)
						vim.notify(entry.path .. " path-copied!", vim.log.levels.INFO)
					end, { buffer = args.data.buf_id, desc = "Copy full path to clipboard" })
				end,
			})

			-- Statusline (replace lualine)
			require("mini.statusline").setup({
				use_icons = true,
				set_vim_settings = true,
				content = {
					active = function()
						local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
						local git = MiniStatusline.section_git({ trunc_width = 40 })
						local diff = MiniStatusline.section_diff({ trunc_width = 75 })
						local diagnostics = MiniStatusline.section_diagnostics({ trunc_width = 75 })
						local lsp = MiniStatusline.section_lsp({ trunc_width = 75 })
						local filename = MiniStatusline.section_filename({ trunc_width = 140 })
						local fileinfo = MiniStatusline.section_fileinfo({ trunc_width = 120 })
						local location = MiniStatusline.section_location({ trunc_width = 75 })
						local search = MiniStatusline.section_searchcount({ trunc_width = 75 })

						local tmux = vim.env.TMUX and "T" or ""

						return MiniStatusline.combine_groups({
							{ hl = mode_hl, strings = { mode, tmux } },
							{ hl = "MiniStatuslineDevinfo", strings = { git, diff, diagnostics, lsp } },
							"%<", -- Mark general truncate point
							{ hl = "MiniStatuslineFilename", strings = { filename } },
							"%=", -- End left alignment
							{ hl = "MiniStatuslineFileinfo", strings = { fileinfo } },
							{ hl = mode_hl, strings = { search, location } },
						})
					end,
				},
			})

			-- Additional mini modules for enhanced functionality
			require("mini.surround").setup() -- Surround actions
			require("mini.comment").setup() -- Comment lines
			require("mini.bracketed").setup() -- Bracketed navigation

			-- New additions for enhanced workflow
			require("mini.pairs").setup() -- Autopairs
			require("mini.indentscope").setup({
				symbol = " ", -- Invisible symbol, just highlights background
				draw = {
					animation = require("mini.indentscope").gen_animation.none(), -- Disable animation
				},
				options = {
					try_as_border = false, -- Don't try to draw as border
				},
			}) -- Indent visualization

			-- Disable indentscope in Neogit and other transient buffers where
			-- the full-buffer indent scan adds noticeable latency.
			vim.api.nvim_create_autocmd("FileType", {
				pattern = {
					"NeogitStatus",
					"NeogitCommitMessage",
					"NeogitLogView",
					"NeogitDiffView",
					"NeogitRebaseTodo",
					"NeogitPopup",
					"gitcommit",
					"gitrebase",
					"help",
					"man",
				},
				callback = function()
					vim.b.miniindentscope_disable = true
				end,
			})

			-- Additional quality-of-life modules
			require("mini.trailspace").setup() -- Trailing whitespace
			require("mini.bufremove").setup() -- Smart buffer removal

			-- Text objects (advanced selection)
			require("mini.ai").setup()

			-- Text alignment
			require("mini.align").setup()

			-- Enhanced operators
			require("mini.operators").setup()

			-- Fuzzy picker
			require("mini.pick").setup()

			-- Line/selection moving via mini.move
			-- Uses <M-S-J/K> (Shift+Alt+J/K) to avoid conflicting with
			-- the <A-h/j/k/l> window navigation shortcuts.
			require("mini.move").setup({
				mappings = {
					-- Move line/selection up/down in normal and visual mode
					line_down = "<M-J>",  -- Alt+Shift+J
          line_up = "<M-K>",    -- Alt+Shift+K
					line_left = "<M-H>",
          line_right = "<M-L>",
        up = "<M-K>",
					down = "<M-J>",
					-- Disable left/right to avoid any accidental conflicts
					left = "<M-H>",
					right = "<M-L>",
				},
			})

			-- Highlight hex colours and TODO/FIXME/NOTE/HACK/WARN inline
			-- (part of mini.nvim, no extra plugin required)
			require("mini.hipatterns").setup({
				highlighters = {
					-- Highlight hex colors: #rrggbb
					hex_color = require("mini.hipatterns").gen_highlighter.hex_color(),
					-- Highlight common annotation keywords
					todo = { pattern = "%f[%w]()TODO()%f[%W]", group = "MiniHipatternsTodo" },
					fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
					hack = { pattern = "%f[%w]()HACK()%f[%W]", group = "MiniHipatternsHack" },
					note = { pattern = "%f[%w]()NOTE()%f[%W]", group = "MiniHipatternsNote" },
					warn = { pattern = "%f[%w]()WARN()%f[%W]", group = "MiniHipatternsFixme" },
				},
			})

			-- Update keymaps to use mini.files instead of oil
			vim.keymap.set(
				"n",
				"<leader>-",
				":lua MiniFiles.open()<CR>",
				{ desc = "Open parent directory (mini.files)" }
			)
			vim.keymap.set("n", "<leader>e", function()
				local bufname = vim.api.nvim_buf_get_name(0)
				-- Check if we're in a neo-tree buffer and use cwd instead
				if bufname:match("neo%-tree") then
					MiniFiles.open(vim.fn.getcwd())
				else
					if vim.fn.filereadable(bufname) == 1 then
						MiniFiles.open(bufname)
					else
						MiniFiles.open(vim.fn.getcwd())
					end
				end
			end, { desc = "Open mini.files in float" })

			-- Keymaps for new mini modules
			vim.keymap.set("n", "<leader>cw", ":lua MiniTrailspace.trim()<CR>", { desc = "Trim trailing whitespace" })
			vim.keymap.set("n", "<leader>bd", ":lua MiniBufremove.delete()<CR>", { desc = "Delete buffer safely" })
			vim.keymap.set("n", "<leader>bw", ":lua MiniBufremove.wipeout()<CR>", { desc = "Wipeout buffer" })
		end,
	},
}
