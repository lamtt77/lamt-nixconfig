-- Leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

local common = require('config.common')

-- ───────────────────────────── Movement ──────────────────────────────────
-- Better j/k: use visual lines when no count, real lines when given a count
vim.keymap.set({ 'n', 'x' }, 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true, desc = 'Down (smart)' })
vim.keymap.set({ 'n', 'x' }, 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true, desc = 'Up (smart)' })
vim.keymap.set({ 'n', 'x' }, '<Down>', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true, desc = 'Down (smart)' })
vim.keymap.set({ 'n', 'x' }, '<Up>', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true, desc = 'Up (smart)' })

-- ──────────────────────── Window resizing ────────────────────────────────
-- Simple window resizing shortcuts
vim.keymap.set({ 'n', 'i' }, '<A-=>', '<C-W>10>', { noremap = true, silent = true, desc = 'Increase window width by 10' })
vim.keymap.set({ 'n', 'i' }, '<A-->', '<C-W>10<', { noremap = true, silent = true, desc = 'Decrease window width by 10' })

-- Window resizing from terminal mode (when actively typing in terminal)
vim.keymap.set('t', '<A-=>', '<C-\\><C-N><C-W>10><C-\\><C-N>i', { noremap = true, silent = true, desc = 'Increase window width by 10 from terminal' })
vim.keymap.set('t', '<A-->', '<C-\\><C-N><C-W>10<<C-\\><C-N>i', { noremap = true, silent = true, desc = 'Decrease window width by 10 from terminal' })


-- ─────────────────────────── Neovim lifecycle ────────────────────────────
-- Reload / restart Neovim config
vim.keymap.set('n', '<leader>R', function()
  vim.cmd.restart()
end, { noremap = true, silent = true, desc = 'Restart Neovim' })

-- Save file (convenience: <C-s> in all modes)
vim.keymap.set({ 'n', 'i', 'v' }, '<C-s>', '<cmd>w<cr><esc>', { desc = 'Save file' })

-- Quit helpers (consistent with <leader>q group used by most distros)
vim.keymap.set('n', '<leader>qq', '<cmd>qa<cr>', { desc = 'Quit all' })

-- ─────────────────────────── Undo / Redo ─────────────────────────────────
vim.keymap.set('n', '<leader>z', 'u', { noremap = true, desc = 'Undo' })
vim.keymap.set('n', '<leader>Z', '<C-r>', { noremap = true, desc = 'Redo' })

-- ──────────────────────────── Theme ──────────────────────────────────────
vim.keymap.set('n', '<leader>tt', common.toggle_theme, { noremap = true, silent = true, desc = 'Toggle Catppuccin / Gruvbox' })
vim.keymap.set('n', '<leader>tL', ':colorscheme catppuccin-latte<CR>:set background=light<CR>', { noremap = true, silent = true, desc = 'Light theme' })
vim.keymap.set('n', '<leader>tD', ':colorscheme catppuccin-mocha<CR>:set background=dark<CR>', { noremap = true, silent = true, desc = 'Dark theme' })

-- ──────────────────────────── Clipboard ──────────────────────────────────
-- yank line / selection to system clipboard
vim.keymap.set('n', '<leader>y', '"+yy', { noremap = true, silent = true, desc = 'Yank line to clipboard' })
vim.keymap.set('v', '<leader>y', '"+y', { noremap = true, silent = true, desc = 'Yank selection to clipboard' })

-- Yank from cursor to end-of-line to clipboard (mirrors the built-in Y behaviour)
vim.keymap.set('n', '<leader>Y', '"+y$', { noremap = true, silent = true, desc = 'Yank to EOL to clipboard' })



-- ─────────────────────── Buffer management ───────────────────────────────
-- Navigate buffers (Shift-H/L + bracket pair)
vim.keymap.set('n', '<S-h>', '<cmd>bprevious<cr>', { desc = 'Prev buffer' })
vim.keymap.set('n', '<S-l>', '<cmd>bnext<cr>', { desc = 'Next buffer' })
vim.keymap.set('n', '[b', '<cmd>bprevious<cr>', { desc = 'Prev buffer' })
vim.keymap.set('n', ']b', '<cmd>bnext<cr>', { desc = 'Next buffer' })
-- Alternate buffer (last visited)
vim.keymap.set('n', '<leader>`', '<cmd>e #<cr>', { desc = 'Switch to other buffer' })

-- ─────────────────────── Directory navigation ────────────────────────────
vim.keymap.set('n', '<leader>cd', ':cd %:p:h<CR>', { desc = 'Change to directory of current file' })

-- Yank filename / path of current buffer to system clipboard
vim.keymap.set('n', '<leader>fy', function()
  local filename = vim.fn.expand('%:t')
  if filename == "" then
    vim.notify("No filename available", vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', filename)
  vim.notify("Yanked filename: " .. filename, vim.log.levels.INFO)
end, { desc = "Yank filename" })

vim.keymap.set('n', '<leader>fY', function()
  local filepath = vim.fn.expand('%:p')
  if filepath == "" then
    vim.notify("No file path available", vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', filepath)
  vim.notify("Yanked full file path: " .. filepath, vim.log.levels.INFO)
end, { desc = "Yank full file path" })

-- ──────────────────── Visual mode quality-of-life ────────────────────────
-- Shift block and stay in visual mode
vim.keymap.set('v', '<', '<gv', { desc = 'Shift left and maintain visual mode' })
vim.keymap.set('v', '>', '>gv', { desc = 'Shift right and maintain visual mode' })

-- ──────────────── Quickfix / location list navigation ────────────────────
vim.keymap.set('n', ']q', ':cnext<CR>zz', { desc = 'Next quickfix item' })
vim.keymap.set('n', '[q', ':cprev<CR>zz', { desc = 'Previous quickfix item' })
vim.keymap.set('n', ']Q', ':clast<CR>zz', { desc = 'Last quickfix item' })
vim.keymap.set('n', '[Q', ':cfirst<CR>zz', { desc = 'First quickfix item' })
vim.keymap.set('n', ']l', ':lnext<CR>zz', { desc = 'Next location list item' })
vim.keymap.set('n', '[l', ':lprev<CR>zz', { desc = 'Previous location list item' })

-- ─────────────────────── Markdown headings ───────────────────────────────
vim.keymap.set('n', '<leader>1', 'm`yypVr=``', { desc = 'Create level 1 heading' })
vim.keymap.set('n', '<leader>2', 'm`yypVr-``', { desc = 'Create level 2 heading' })
vim.keymap.set('n', '<leader>3', 'm`^i### <esc>``4l', { desc = 'Create level 3 heading' })
vim.keymap.set('n', '<leader>4', 'm`^i#### <esc>``5l', { desc = 'Create level 4 heading' })
vim.keymap.set('n', '<leader>5', 'm`^i##### <esc>``6l', { desc = 'Create level 5 heading' })

-- ─────────────────────────── Spell checking ──────────────────────────────
vim.keymap.set('n', '<leader>ss', ':set spell!<CR>', { desc = 'Toggle spell checking' })
vim.keymap.set('n', '<leader>sf', '1z=', { desc = 'Fix with first suggestion' })
vim.keymap.set('n', '<leader>s.', '<cmd>spellrepall<CR>', { desc = 'Repeat last spell replacement' })

-- ──────────────── Search highlight clear ─────────────────────────────────
-- <C-c> clears search highlights; avoids conflict with tmux prefix (<C-l>)
vim.keymap.set('n', '<C-c>', ':nohlsearch<CR>', { noremap = true, silent = true, desc = 'Clear search highlights' })

-- ─────────────────────── Treesitter helpers ──────────────────────────────
vim.keymap.set('n', '<leader>tsu', ':TSUpdate<CR>', { desc = 'Update treesitter parsers' })
vim.keymap.set('n', '<leader>tsi', ':TSConfigInfo<CR>', { desc = 'Show treesitter config' })
vim.keymap.set('n', '<leader>tsh', ':Inspect<CR>', { desc = 'Show highlight group under cursor' })

-- ─────────────────── Tmux-aware window navigation ────────────────────────
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

    -- Fall back to tmux if we didn't move to a new split
    vim.schedule(function()
      if vim.fn.winnr() == current_win then
        tmux_navigate(dir)
      end
    end)
  end
end

-- Alt-HJKL: navigate vim splits or tmux panes transparently
vim.keymap.set({ 'n', 'v', 'i', 't' }, '<A-h>', function() navigate('h') end, { desc = 'Navigate left (split/pane)' })
vim.keymap.set({ 'n', 'v', 'i', 't' }, '<A-j>', function() navigate('j') end, { desc = 'Navigate down (split/pane)' })
vim.keymap.set({ 'n', 'v', 'i', 't' }, '<A-k>', function() navigate('k') end, { desc = 'Navigate up (split/pane)' })
vim.keymap.set({ 'n', 'v', 'i', 't' }, '<A-l>', function() navigate('l') end, { desc = 'Navigate right (split/pane)' })

-- ─────────────────────────── Tab navigation ──────────────────────────────
vim.keymap.set('n', '[t', ':tabprevious<CR>', { noremap = true, silent = true, desc = 'Previous tab' })
vim.keymap.set('n', ']t', ':tabnext<CR>', { noremap = true, silent = true, desc = 'Next tab' })
