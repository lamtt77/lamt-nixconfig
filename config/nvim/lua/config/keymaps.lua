-- Leader key
vim.g.mapleader = ' '

local common = require('config.common')

-- Simple window resizing shortcuts
vim.keymap.set({'n', 'i'}, '<A-=>', '<C-W>10>', { noremap = true, silent = true, desc = 'Increase window width by 10' })
vim.keymap.set({'n', 'i'}, '<A-->', '<C-W>10<', { noremap = true, silent = true, desc = 'Decrease window width by 10' })

-- Window resizing from terminal mode (when actively typing in terminal)
vim.keymap.set('t', '<A-=>', '<C-\\><C-N><C-W>10><C-\\><C-N>i', { noremap = true, silent = true, desc = 'Increase window width by 10 from terminal' })
vim.keymap.set('t', '<A-->', '<C-\\><C-N><C-W>10<<C-\\><C-N>i', { noremap = true, silent = true, desc = 'Decrease window width by 10 from terminal' })

-- Reload Neovim config
vim.keymap.set('n', '<leader>R', function()
  vim.cmd.restart()
end, { noremap = true, silent = true, desc = 'Restart Neovim' })

-- Undo/Redo keybindings
vim.keymap.set('n', '<leader>z', 'u', { noremap = true, desc = 'Undo' })
vim.keymap.set('n', '<leader>Z', '<C-r>', { noremap = true, desc = 'Redo' })

-- Theme switching
vim.keymap.set('n', '<leader>tt', common.toggle_theme, { noremap = true, silent = true, desc = 'Toggle theme' })

vim.keymap.set('n', '<leader>tl', ':colorscheme catppuccin-latte<CR>:set background=light<CR>', { noremap = true, silent = true, desc = 'Light theme' })
vim.keymap.set('n', '<leader>td', ':colorscheme catppuccin-mocha<CR>:set background=dark<CR>', { noremap = true, silent = true, desc = 'Dark theme' })

-- Clipboard mappings
vim.keymap.set('n', '<leader>y', '"+yy', { noremap = true, silent = true, desc = 'Yank line to clipboard' })
vim.keymap.set('v', '<leader>y', '"+y', { noremap = true, silent = true, desc = 'Yank selection to clipboard' })
vim.keymap.set('n', '<leader>p', '"+p', { noremap = true, silent = true, desc = 'Paste after cursor from clipboard' })
vim.keymap.set('n', '<leader>P', '"+P', { noremap = true, silent = true, desc = 'Paste before cursor from clipboard' })

-- Directory navigation
vim.keymap.set('n', '<leader>cd', ':cd %:p:h<CR>', { desc = 'Change to directory of current file' })

-- Visual mode shifting with selection maintenance
vim.keymap.set('v', '<', '<gv', { desc = 'Shift left and maintain visual mode' })
vim.keymap.set('v', '>', '>gv', { desc = 'Shift right and maintain visual mode' })

-- Quickfix and location list navigation
vim.keymap.set('n', ']q', ':cnext<CR>zz', { desc = 'Next quickfix item' })
vim.keymap.set('n', '[q', ':cprev<CR>zz', { desc = 'Previous quickfix item' })
vim.keymap.set('n', ']l', ':lnext<CR>zz', { desc = 'Next location list item' })
vim.keymap.set('n', '[l', ':lprev<CR>zz', { desc = 'Previous location list item' })

-- Markdown heading creation shortcuts
vim.keymap.set('n', '<leader>1', 'm`yypVr=``', { desc = 'Create level 1 heading' })
vim.keymap.set('n', '<leader>2', 'm`yypVr-``', { desc = 'Create level 2 heading' })
vim.keymap.set('n', '<leader>3', 'm`^i### <esc>``4l', { desc = 'Create level 3 heading' })
vim.keymap.set('n', '<leader>4', 'm`^i#### <esc>``5l', { desc = 'Create level 4 heading' })
vim.keymap.set('n', '<leader>5', 'm`^i##### <esc>``6l', { desc = 'Create level 5 heading' })

-- Spell checking keybindings
vim.keymap.set('n', '<leader>ss', ':set spell!<CR>', { desc = 'Toggle spell checking' })
vim.keymap.set('n', '<leader>sf', '1z=', { desc = 'Fix with first suggestion' })
vim.keymap.set('n', '<leader>s.', '<cmd>spellrepall<CR>', { desc = 'Repeat last spell replacement' })

-- Clear search highlights with C-c instead of C-l (to avoid tmux prefix conflict)
vim.keymap.set('n', '<C-c>', ':nohlsearch<CR>', { noremap = true, silent = true, desc = 'Clear search highlights' })

-- Treesitter troubleshooting keybindings
vim.keymap.set('n', '<leader>tsu', ':TSUpdate<CR>', { desc = 'Update treesitter parsers' })
vim.keymap.set('n', '<leader>tsi', ':TSConfigInfo<CR>', { desc = 'Show treesitter config' })
vim.keymap.set('n', '<leader>tsh', ':Inspect<CR>', { desc = 'Show highlight group under cursor' })

-- Custom tmux navigation
local function tmux_navigate(dir)
  local tmux_dirs = { h = 'L', j = 'D', k = 'U', l = 'R' }
  local tmux_dir = tmux_dirs[dir]
  if tmux_dir then
    vim.fn.system('tmux select-pane -' .. tmux_dir)
  end
end

local function navigate(dir)
  local win_cmd = ({ h = 'h', j = 'j', k = 'k', l = 'l' })[dir]
  if win_cmd then
    local mode = vim.api.nvim_get_mode().mode
    local current_win = vim.fn.winnr()

    if mode == 'i' or mode == 't' then
      -- In insert or terminal mode, use escape sequence
      local key_seq = '<C-\\><C-N><C-W>' .. win_cmd
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key_seq, true, false, true), 'n', false)
    else
      -- In normal/visual mode, use wincmd
      vim.cmd('wincmd ' .. win_cmd)
    end

    -- Check if window navigation succeeded, if not try tmux
    vim.defer_fn(function()
      if vim.fn.winnr() == current_win then
        tmux_navigate(dir)
      end
    end, 0)
  end
end

-- Window navigation with Alt-HJKL (vim split or tmux pane)
vim.keymap.set({'n', 'v', 'i', 't'}, '<A-h>', function() navigate('h') end, { desc = 'Navigate left (vim split or tmux pane)' })
vim.keymap.set({'n', 'v', 'i', 't'}, '<A-j>', function() navigate('j') end, { desc = 'Navigate down (vim split or tmux pane)' })
vim.keymap.set({'n', 'v', 'i', 't'}, '<A-k>', function() navigate('k') end, { desc = 'Navigate up (vim split or tmux pane)' })
vim.keymap.set({'n', 'v', 'i', 't'}, '<A-l>', function() navigate('l') end, { desc = 'Navigate right (vim split or tmux pane)' })

-- Tab navigation
vim.keymap.set('n', '[t', ':tabprevious<CR>', { noremap = true, silent = true, desc = 'Previous tab' })
vim.keymap.set('n', ']t', ':tabnext<CR>', { noremap = true, silent = true, desc = 'Next tab' })
