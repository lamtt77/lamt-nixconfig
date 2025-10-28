-- Custom commands
vim.cmd("command! SudoWrite execute 'silent! write !sudo tee % >/dev/null' | edit!")