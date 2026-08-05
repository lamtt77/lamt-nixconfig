-- :StartupProfile — timeline of startup work that --startuptime can't see.
-- --startuptime stops at "first screen update"; session restore and LSP attach
-- happen after that, and are usually where real startup time goes.
--
-- t0 is the first line of init.lua. Neovim exposes no process-start timestamp
-- (uv.uptime() is system uptime), so the ~5ms the C startup spends before
-- init.lua is sourced is not counted here; --startuptime covers that part.

local M = {}

local t0 = vim.g._startup_t0_ns or vim.uv.hrtime()
local marks = {}

local function mark(name)
	marks[#marks + 1] = { name = name, ms = (vim.uv.hrtime() - t0) / 1e6 }
end

local group = vim.api.nvim_create_augroup("StartupProfile", { clear = true })

for _, ev in ipairs({ "UIEnter", "VimEnter", "SessionLoadPost" }) do
	vim.api.nvim_create_autocmd(ev, { group = group, callback = function() mark(ev) end })
end

vim.api.nvim_create_autocmd("BufReadPost", {
	group = group,
	callback = function(a) mark("BufReadPost " .. vim.fn.fnamemodify(a.file or "", ":t")) end,
})

-- Files named on the command line are read before init.lua is sourced, so no
-- BufReadPost fires for them. Note them once so the timeline isn't misleading.
vim.api.nvim_create_autocmd("VimEnter", {
	group = group,
	once = true,
	callback = function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(buf)
			if vim.api.nvim_buf_is_loaded(buf) and name ~= "" then
				mark("(pre-init) " .. vim.fn.fnamemodify(name, ":t"))
			end
		end
	end,
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = group,
	callback = function(a)
		local c = vim.lsp.get_client_by_id(a.data.client_id)
		mark("LspAttach " .. ((c and c.name) or "?"))
	end,
})

function M.report()
	local lines = { "Startup timeline (t0 = init.lua line 1):", "" }
	for _, m in ipairs(marks) do
		lines[#lines + 1] = string.format("%9.2f ms  %s", m.ms, m.name)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = string.format("%9d     buffers", #vim.api.nvim_list_bufs())
	local names = {}
	for _, c in ipairs(vim.lsp.get_clients()) do
		names[#names + 1] = c.name
	end
	lines[#lines + 1] = "           clients: " .. (#names > 0 and table.concat(names, ", ") or "none")
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("StartupProfile", M.report, {
	desc = "Show startup timeline including post-UIEnter work",
})

return M
