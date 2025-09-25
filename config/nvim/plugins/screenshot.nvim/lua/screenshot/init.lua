local config = require("screenshot.config")
local core = require("screenshot.core")
local commands = require("screenshot.commands")

local M = {}

-- Setup function for lazy.nvim
function M.setup(user_config)
  -- Apply user configuration
  config.setup(user_config)

  -- Register user commands
  commands.register_commands()

  -- Register key mappings
  M.register_keymaps()
end

-- Register key mappings
function M.register_keymaps()
  local keymaps = config.get().keymaps

  -- Global key mappings
  vim.keymap.set('n', keymaps.interactive, core.take_screenshot_interactive, {
    desc = 'Take interactive screenshot (local ./images/)'
  })

  vim.keymap.set('n', keymaps.fullscreen, core.take_fullscreen_screenshot, {
    desc = 'Take fullscreen screenshot (local ./images/)'
  })

  vim.keymap.set('n', keymaps.interactive_global, core.take_screenshot_interactive_global, {
    desc = 'Take interactive screenshot (global ~/.local/nvim_screenshots/)'
  })

  vim.keymap.set('n', keymaps.fullscreen_global, core.take_fullscreen_screenshot_global, {
    desc = 'Take fullscreen screenshot (global ~/.local/nvim_screenshots/)'
  })

  vim.keymap.set('n', keymaps.check, ':ScreenshotCheck<CR>', {
    desc = 'Check screenshot tool availability'
  })

  vim.keymap.set('n', keymaps.directory, core.open_screenshot_directory, {
    desc = 'Open screenshot directory'
   })

   -- Filetype-specific mappings for markdown
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'markdown',
    callback = function()
      vim.keymap.set('n', keymaps.interactive, core.take_screenshot_interactive, {
        buffer = true,
        desc = 'Take screenshot (local ./images/)'
      })
      vim.keymap.set('n', keymaps.fullscreen, core.take_fullscreen_screenshot, {
        buffer = true,
        desc = 'Take fullscreen screenshot (local ./images/)'
      })
      vim.keymap.set('n', keymaps.interactive_global, core.take_screenshot_interactive_global, {
        buffer = true,
        desc = 'Take screenshot (global ~/.local/nvim_screenshots/)'
      })
      vim.keymap.set('n', keymaps.fullscreen_global, core.take_fullscreen_screenshot_global, {
        buffer = true,
        desc = 'Take fullscreen screenshot (global ~/.local/nvim_screenshots/)'
      })

    end,
  })
end

-- Expose core functions for direct access if needed
M.take_screenshot = core.take_screenshot
M.take_screenshot_interactive = core.take_screenshot_interactive
M.take_fullscreen_screenshot = core.take_fullscreen_screenshot
M.take_screenshot_interactive_global = core.take_screenshot_interactive_global
M.take_fullscreen_screenshot_global = core.take_fullscreen_screenshot_global
M.open_screenshot_directory = core.open_screenshot_directory

-- Expose commands for direct access if needed
M.image_status = commands.image_status
M.screenshot_check = commands.screenshot_check

return M