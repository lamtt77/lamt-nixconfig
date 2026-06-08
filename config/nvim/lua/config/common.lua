-- Common utility functions shared across modules

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
  toggle_theme = toggle_theme,
}
