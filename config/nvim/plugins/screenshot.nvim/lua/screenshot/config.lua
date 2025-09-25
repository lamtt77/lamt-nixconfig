local M = {}

-- Default configuration
M.defaults = {
  -- Directory where local screenshots are saved (relative to current buffer's directory)
  -- Also used as base for markdown links (with trailing slash added automatically)
  local_screenshot_dir = "./images",

  -- Global directory for screenshots (absolute path, for shared screenshots)
  global_screenshot_dir = "~/.local/nvim_screenshots",

  -- Key mappings
  keymaps = {
    interactive = "<leader>ss",     -- Take interactive screenshot (local)
    fullscreen = "<leader>sf",      -- Take fullscreen screenshot (local)
    interactive_global = "<leader>sS", -- Take interactive screenshot (global)
    fullscreen_global = "<leader>sF", -- Take fullscreen screenshot (global)
    check = "<leader>sc",           -- Check screenshot tool availability
    directory = "<leader>sd",       -- Open screenshot directory
    toggle_images = "<leader>ti",   -- Toggle inline image display
  },

  -- Platform-specific tool preferences (in order of preference)
  tools = {
    linux = { "maim", "scrot", "flameshot" },
    clipboard = { "xclip", "wl-copy" },
  },

  -- Whether to automatically copy screenshots to clipboard
  auto_clipboard = true,

  -- Whether to insert markdown links automatically
  auto_insert = true,

  -- File naming pattern (uses os.date format)
  filename_pattern = "screenshot_%Y%m%d_%H%M%S.png",
  fullscreen_pattern = "fullscreen_%Y%m%d_%H%M%S.png",
}

-- Current configuration (starts with defaults)
M.current = vim.deepcopy(M.defaults)

-- Setup function to merge user config with defaults
function M.setup(user_config)
  M.current = vim.tbl_deep_extend("force", M.defaults, user_config or {})
end

-- Get current configuration
function M.get()
  return M.current
end

return M