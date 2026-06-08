-- Plugin configuration for Neovim LSP setup
-- This file sets up the plugin manager and required plugins

-- Bootstrap lazy.nvim if not installed
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
---@type uv
if not vim.uv.fs_stat(lazypath) then
  local result = vim.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  }, { text = true }):wait()
  if result.code ~= 0 then
    error("Failed to clone lazy.nvim:\n" .. (result.stderr or "unknown error"))
  end
end
vim.opt.rtp:prepend(lazypath)

-- Plugin specifications - now loaded from modular config files
-- Setup lazy.nvim
require("lazy").setup({
  -- Import configurations from modular files
  { import = "config.completion" },
  { import = "config.lsp" },
  { import = "config.dap" },
  { import = "config.telescope" },
  { import = "config.file-explorer" },
  { import = "config.theme" },
  { import = "config.workspace" },
  { import = "config.ai" },
  { import = "config.git" },
  { import = "config.utils" },
  { import = "config.formatting" },
  { import = "config.linting" },
  { import = "config.markdown" },
}, {
  performance = {
    rtp = { reset = false },
  },
})
