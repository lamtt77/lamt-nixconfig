" screenshot.nvim - Cross-platform screenshot integration for Neovim
"
" This plugin provides cross-platform screenshot functionality
" with automatic markdown link insertion and clipboard integration.

if exists('g:loaded_screenshot')
  finish
endif
let g:loaded_screenshot = 1

" The plugin is primarily Lua-based, so no additional Vimscript needed