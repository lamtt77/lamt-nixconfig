-- Custom commands
vim.api.nvim_create_user_command("SudoWrite", function()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		vim.notify("SudoWrite requires a file-backed buffer", vim.log.levels.ERROR)
		return
	end

	vim.cmd("silent write !sudo tee " .. vim.fn.shellescape(path) .. " >/dev/null")
	vim.cmd.edit({ bang = true })
end, { desc = "Write the current buffer with sudo" })

-- Force stop all LSP clients on exit to avoid slow shutdown hangs
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("LspForceStopOnExit", { clear = true }),
	callback = function()
		local clients = vim.lsp.get_clients()
		for _, client in ipairs(clients) do
			pcall(function()
				client:stop(true)
			end)
		end
	end,
})
