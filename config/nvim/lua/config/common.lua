-- Common utility functions shared across modules

--- Toggle between catppuccin and gruvbox themes
local function toggle_theme()
  local current = vim.g.colors_name or ""
  if current:find("catppuccin") then
    vim.cmd("colorscheme gruvbox")
    print("Switched to gruvbox theme")
  else
    vim.cmd("colorscheme catppuccin")
    print("Switched to catppuccin theme")
  end
end

return {
  toggle_theme = toggle_theme,
}
