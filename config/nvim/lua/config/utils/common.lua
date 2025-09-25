-- Common utility functions shared across modules

--- Check if the current directory is a git repository
---@return boolean
local function is_git_repo()
  local handle = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result:match("true") ~= nil
  end
  return false
end

--- Toggle between light and dark catppuccin themes
local function toggle_theme()
  if vim.o.background == 'dark' then
    vim.o.background = 'light'
    vim.cmd('colorscheme catppuccin-latte')
    print('Switched to light theme')
  else
    vim.o.background = 'dark'
    vim.cmd('colorscheme catppuccin-mocha')
    print('Switched to dark theme')
  end
end

return {
  is_git_repo = is_git_repo,
  toggle_theme = toggle_theme,
}