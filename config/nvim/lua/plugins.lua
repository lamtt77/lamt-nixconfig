-- Plugin configuration for Neovim LSP setup
-- This file sets up the plugin manager and required plugins

-- Bootstrap lazy.nvim if not installed
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
---@type uv
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Plugin specifications - now loaded from modular config files
local plugins = {}

-- Load plugin configurations from modular files
local plugin_files = {
  'config.completion',
  'config.lsp',
  'config.dap',
  'config.telescope',
  'config.file-explorer',
  'config.theme',
  'config.workspace',
  'config.ai',
  'config.git',
  'config.utils',
  'config.formatting',
  'config.linting',
}

for _, file in ipairs(plugin_files) do
  local ok, module_plugins = pcall(require, file)
  if ok and type(module_plugins) == 'table' then
    for _, plugin in ipairs(module_plugins) do
      table.insert(plugins, plugin)
    end
  else
    vim.notify("Failed to load plugin config from " .. file, vim.log.levels.WARN)
  end
end

-- Setup lazy.nvim
require("lazy").setup(plugins, {
  performance = {
    rtp = { reset = false },
  },
})
