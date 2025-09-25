return {
  -- Undo tree
  {
    "mbbill/undotree",
    cmd = "UndotreeToggle",
    config = function()
      -- Undotree configuration
      vim.g.undotree_WindowLayout = 2
      vim.g.undotree_ShortIndicators = 1
      vim.g.undotree_SplitWidth = 40
      vim.g.undotree_SetFocusWhenToggle = 1

      -- Key mapping for undotree
      vim.keymap.set('n', '<leader>ut', ':UndotreeToggle<CR>', { noremap = true, silent = true, desc = 'Toggle undo tree' })
    end,
  },
}