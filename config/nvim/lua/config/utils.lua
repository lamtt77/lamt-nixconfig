-- Utils plugins - now loads from submodules
local plugins = {}

-- Load utils plugin configurations from submodules
local utils_files = {
  'config.utils.mini',      -- All Mini modules combined
  'config.utils.editing',   -- vim-visual-multi
  'config.utils.search',    -- spectre
  'config.utils.undo',      -- undotree
  'config.utils.media',     -- screenshot, image
}

for _, file in ipairs(utils_files) do
  local ok, module_plugins = pcall(require, file)
  if ok and type(module_plugins) == 'table' then
    for _, plugin in ipairs(module_plugins) do
      table.insert(plugins, plugin)
    end
  else
    vim.notify("Failed to load utils plugin config from " .. file, vim.log.levels.WARN)
  end
end

return plugins