-- vim-rsi inspired mappings for readline-style navigation in insert and command modes
-- Insert mode mappings
vim.keymap.set('i', '<M-b>', '<S-Left>', { desc = 'Move to previous word' })
vim.keymap.set('i', '<M-f>', '<S-Right>', { desc = 'Move to next word' })
vim.keymap.set('i', '<M-d>', '<C-O>dw', { desc = 'Delete word forward' })
vim.keymap.set('i', '<M-n>', '<Down>', { desc = 'Move down' })
vim.keymap.set('i', '<M-p>', '<Up>', { desc = 'Move up' })
vim.keymap.set('i', '<C-A>', '<C-O>^', { desc = 'Move to beginning of line' })
vim.keymap.set('i', '<C-X><C-A>', '<C-A>', { desc = 'Fallback C-A' })
vim.keymap.set('i', '<C-B>', function()
  local line = vim.fn.getline('.')
  local col = vim.fn.col('.')
  if line:match('^%s*$') and col > #line then
    return '0<C-D><Esc>kJs'
  else
    return '<Left>'
  end
end, { expr = true, desc = 'Smart left movement' })
vim.keymap.set('i', '<C-D>', function()
  if vim.fn.col('.') > #vim.fn.getline('.') then
    return '<C-D>'
  else
    return '<Del>'
  end
end, { expr = true, desc = 'Smart delete' })
vim.keymap.set('i', '<C-E>', function()
  if vim.fn.col('.') > #vim.fn.getline('.') or vim.fn.pumvisible() == 1 then
    return '<C-E>'
  else
    return '<End>'
  end
end, { expr = true, desc = 'Smart end of line' })
vim.keymap.set('i', '<C-F>', function()
  if vim.fn.col('.') > #vim.fn.getline('.') then
    return '<C-F>'
  else
    return '<Right>'
  end
end, { expr = true, desc = 'Smart right movement' })

-- Command mode mappings
vim.keymap.set('c', '<M-b>', '<S-Left>', { desc = 'Move to previous word' })
vim.keymap.set('c', '<M-f>', '<S-Right>', { desc = 'Move to next word' })
vim.keymap.set('c', '<M-d>', '<S-Right><C-W>', { desc = 'Delete word forward' })
vim.keymap.set('c', '<M-n>', '<Down>', { desc = 'Move down' })
vim.keymap.set('c', '<M-p>', '<Up>', { desc = 'Move up' })
vim.keymap.set('c', '<C-A>', '<Home>', { desc = 'Move to beginning of line' })
vim.keymap.set('c', '<C-X><C-A>', '<C-A>', { desc = 'Fallback C-A' })
vim.keymap.set('c', '<C-B>', '<Left>', { desc = 'Move left' })
vim.keymap.set('c', '<C-D>', function()
  if vim.fn.getcmdpos() > #vim.fn.getcmdline() then
    return '<C-D>'
  else
    return '<Del>'
  end
end, { expr = true, desc = 'Smart delete' })
vim.keymap.set('c', '<C-F>', function()
  if vim.fn.getcmdpos() > #vim.fn.getcmdline() then
    return vim.o.cedit
  else
    return '<Right>'
  end
end, { expr = true, desc = 'Smart right movement' })