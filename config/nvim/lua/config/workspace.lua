local function prepareForRestore()
	if package.loaded["mini.files"] then
		pcall(require("mini.files").close)
	end

	for _, window in ipairs(vim.api.nvim_list_wins()) do
		vim.wo[window].winfixbuf = false
	end
end

local function finishRestore()
	vim.schedule(function()
		if package.loaded["mini.files"] then
			pcall(require("mini.files").close)
		end
	end)
end

local workspaceRoots = {
	vim.fn.expand("~/lamt-nixconfig"),
	vim.fn.expand("~/lab"),
	vim.fn.expand("~/work"),
}

local function discoverRepositories()
	local seen = {}
	for _, root in ipairs(workspaceRoots) do
		if vim.fn.isdirectory(root) == 1 then
			if vim.uv.fs_stat(vim.fs.joinpath(root, ".git")) then
				seen[root] = true
			end
			local result = vim.system({
				"fd",
				"--absolute-path",
				"--hidden",
				"--no-ignore",
				"--max-depth",
				"5",
				"^\\.git$",
				root,
			}, { text = true }):wait()
			if result.code == 0 and result.stdout then
				for marker in result.stdout:gmatch("[^\r\n]+") do
					seen[vim.fs.dirname(marker:gsub("[/\\]+$", ""))] = true
				end
			end
		end
	end
	local repos = vim.tbl_keys(seen)
	table.sort(repos)
	return repos
end

local function switchRepository()
	local repos = discoverRepositories()
	if vim.tbl_isempty(repos) then
		vim.notify("No Git repositories found in configured workspace roots", vim.log.levels.WARN)
		return
	end
	require("telescope.pickers")
		.new({}, {
			prompt_title = "Switch Repository",
			finder = require("telescope.finders").new_table({ results = repos }),
			sorter = require("telescope.config").values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				require("telescope.actions").select_default:replace(function()
					require("telescope.actions").close(prompt_bufnr)
					local sel = require("telescope.actions.state").get_selected_entry()
					if sel then
						vim.api.nvim_set_current_dir(sel.value)
					end
				end)
				return true
			end,
		})
		:find()
end

local function isWorkspaceDirectory()
	local cwd = vim.fs.normalize(vim.fn.getcwd(-1, -1))
	for _, root in ipairs(workspaceRoots) do
		if cwd == root or vim.startswith(cwd, root .. "/") then
			return true
		end
	end
	return false
end

return {
	{
		"rmagatti/auto-session",
		lazy = false,
		init = function()
			vim.o.autoread = true
			vim.opt.shortmess:append("A")
		end,
		keys = {
			{ "<leader>ww", switchRepository, desc = "Switch repository" },
			{
				"<leader>wr",
				function()
					require("telescope") -- Force lazy load just in time
					vim.cmd("AutoSession search")
				end,
				desc = "Search sessions",
			},
			{ "<leader>ws", "<cmd>AutoSession save<CR>", desc = "Save session" },
			{ "<leader>wR", "<cmd>AutoSession restore<CR>", desc = "Restore session" },
			{ "<leader>wd", "<cmd>AutoSession delete<CR>", desc = "Delete session" },
			{
				"<leader>wl",
				function()
					local auto_session = require("auto-session")
					local lib = require("auto-session.lib")
					local config = require("auto-session.config")
					local alternate_session_name = lib.get_alternate_session_name(config.session_lens.session_control)
					if alternate_session_name then
						auto_session.autosave_and_restore(alternate_session_name)
					else
						vim.notify("There is no alternate session", vim.log.levels.WARN)
					end
				end,
				desc = "Toggle alternate session",
			},
			{
				"<leader>wa",
				"<cmd>AutoSession toggle<CR>",
				desc = "Toggle automatic sessions",
			},
			{
				"<leader>wp",
				"<cmd>AutoSession purgeOrphaned<CR>",
				desc = "Purge orphaned sessions",
			},
		},
		---enables autocomplete for opts
		---@module "auto-session"
		---@type AutoSession.Config
		opts = {
			auto_restore = true,
			auto_save = true,
			auto_create = isWorkspaceDirectory,
			auto_restore_last_session = false,
			args_allow_single_directory = true,
			args_allow_files_auto_save = false,
			cwd_change_handling = true,
			lazy_support = true,
			pre_save_cmds = { isWorkspaceDirectory },
			pre_restore_cmds = { prepareForRestore },
			post_restore_cmds = { finishRestore },
			suppressed_dirs = {
				"~/",
				"/",
				"/tmp",
			},
			bypass_save_filetypes = {
				"minifiles",
				"neo-tree",
			},
			close_filetypes_on_save = {
				"checkhealth",
				"help",
				"man",
				"qf",
				"gitcommit",
				"gitrebase",
				"NeogitStatus",
				"NeogitCommitMessage",
				"NeogitLogView",
				"NeogitDiffView",
				"NeogitRebaseTodo",
				"dap-repl",
				"dapui_breakpoints",
				"dapui_console",
				"dapui_scopes",
				"dapui_stacks",
				"dapui_watches",
			},
			session_lens = {
				load_on_setup = false, -- Don't eagerly load telescope extensions on startup
				picker = "telescope",
				previewer = "summary",
				mappings = {
					delete_session = { "i", "<C-d>" },
					copy_session = { "i", "<C-y>" },
					alternate_session = { "i", "<C-a>" },
				},
				theme_conf = {
					border = true,
					winblend = 10,
				},
				picker_opts = {
					height = 0.75,
					width = 0.8,
					border = "rounded",
				},
			},
		},
	},
}
