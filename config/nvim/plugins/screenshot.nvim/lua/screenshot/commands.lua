local config = require("screenshot.config")

local M = {}

-- Image status command
function M.image_status()
  local image_available = pcall(require, 'image')

  print('📸 Cross-Platform Image Integration Status:')
  print('  image.nvim (inline display): ' .. (image_available and '✅ Available' or '❌ Not loaded'))
  print('  Custom screenshot functions: ✅ Available')

  -- Detect platform and available tools
  if vim.fn.has('mac') == 1 then
    print('  Platform: macOS ✅ (screencapture available)')
    print('  Native screenshot: ✅ Available')
  elseif vim.fn.has('unix') == 1 then
    local tools = {}
    local tool_names = config.get().tools.linux
    for _, tool in ipairs(tool_names) do
      if vim.fn.executable(tool) == 1 then
        table.insert(tools, tool)
      end
    end
    if #tools > 0 then
      print('  Platform: Linux ✅ (' .. table.concat(tools, ', ') .. ' available)')
    else
      print('  Platform: Linux ⚠️ (no screenshot tools found)')
    end
  elseif vim.fn.has('win32') == 1 then
    print('  Platform: Windows ✅ (PowerShell available)')
  else
    print('  Platform: Unknown ⚠️')
  end

  print('')
  print('🎯 Keybindings:')
  local keymaps = config.get().keymaps
  print('  ' .. keymaps.interactive .. ' - Take interactive screenshot and insert in markdown')
  print('  ' .. keymaps.fullscreen .. ' - Take fullscreen screenshot')
  print('  ' .. keymaps.check .. ' - Check screenshot tool availability')
  print('  ' .. keymaps.directory .. ' - Open screenshot directory')
  print('  ' .. keymaps.toggle_images .. ' - Toggle inline image display')
  print('')
   print('📁 Local screenshots: ' .. config.get().local_screenshot_dir .. ' (relative to current buffer)')
   print('🌐 Global screenshots: ' .. config.get().global_screenshot_dir)
  print('📋 Clipboard: ' .. (config.get().auto_clipboard and 'Automatically copied when possible' or 'Disabled'))
  print('💡 Tip: Screenshots include timestamps and are automatically inserted as markdown links')

  -- Provide installation instructions if needed
  if vim.fn.has('unix') == 1 then
    local has_tools = false
    for _, tool in ipairs(config.get().tools.linux) do
      if vim.fn.executable(tool) == 1 then
        has_tools = true
        break
      end
    end

    if not has_tools then
      print('')
      print('📦 Linux Installation (choose one):')
      print('  Ubuntu/Debian: sudo apt install maim')
      print('  Arch: sudo pacman -S maim')
      print('  Fedora: sudo dnf install maim')
      print('  Or: sudo apt install scrot')
      print('  Or: sudo snap install flameshot')
    end
  end
end

-- Screenshot setup validation
function M.screenshot_check()
  print('🔍 Screenshot Tool Detection:')

  if vim.fn.has('mac') == 1 then
    print('  macOS screencapture: ✅ Available (native screenshot tool)')
  elseif vim.fn.has('unix') == 1 then
    local tool_names = config.get().tools.linux
    for _, tool in ipairs(tool_names) do
      local status = vim.fn.executable(tool) == 1 and '✅ Available' or '❌ Not found'
      print('  ' .. tool .. ': ' .. status)
    end
  elseif vim.fn.has('win32') == 1 then
    print('  Windows PowerShell: ✅ Available')
  end

  print('')
  print('📁 Local screenshots: ' .. config.get().local_screenshot_dir .. ' (relative to current buffer)')
  print('🌐 Global screenshots: ' .. config.get().global_screenshot_dir)
  print('📄 Default markdown links: ' .. config.get().local_screenshot_dir .. '/ (relative to current buffer)')
  print('🖼️  Image display: ./images/ (relative to current file)')
end

-- Register user commands
function M.register_commands()
  vim.api.nvim_create_user_command('ImageStatus', M.image_status, {
    desc = 'Show cross-platform image integration status'
  })

  vim.api.nvim_create_user_command('ScreenshotCheck', M.screenshot_check, {
    desc = 'Check screenshot tool availability'
  })
end

return M