local config = require("screenshot.config")

local M = {}

-- Helper function to remove empty images directories
local function cleanup_empty_images_dir(dir)
  if vim.fn.isdirectory(dir) == 1 then
    local files = vim.fn.glob(dir .. '/*', false, true)
    if #files == 0 then
      vim.fn.delete(dir, 'rf')
    end
  end
end

-- Get platform-specific screenshot command
function M.get_screenshot_command(filename, interactive)
  local cmd

  if vim.fn.has('mac') == 1 then
    -- macOS: use native screencapture for both interactive and fullscreen
    if interactive then
      cmd = string.format('screencapture -i "%s"', filename)
    else
      cmd = string.format('screencapture -x "%s"', filename)
    end
  elseif vim.fn.has('unix') == 1 then
    -- Linux: try different screenshot tools in order of preference
    local tools = config.get().tools.linux
    for _, tool in ipairs(tools) do
      if vim.fn.executable(tool) == 1 then
        if tool == 'maim' then
          if interactive then
            cmd = string.format('maim -s "%s"', filename)
          else
            cmd = string.format('maim "%s"', filename)
          end
        elseif tool == 'scrot' then
          if interactive then
            cmd = string.format('scrot -s "%s"', filename)
          else
            cmd = string.format('scrot "%s"', filename)
          end
        elseif tool == 'flameshot' then
          if interactive then
            cmd = string.format('flameshot gui -p "%s"', filename)
          else
            cmd = string.format('flameshot full -p "%s"', filename)
          end
        end
        break
      end
    end

    if not cmd then
      print('No screenshot tool found. Please install maim, scrot, or flameshot on Linux.')
      return nil
    end
  elseif vim.fn.has('win32') == 1 then
    -- Windows: PowerShell screenshot
    if interactive then
      cmd = string.format([[powershell -command "
Add-Type -AssemblyName System.Windows.Forms;
$screenshot = New-Object System.Windows.Forms.Bitmap(`
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, `
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height);
$graphics = [System.Drawing.Graphics]::FromImage($screenshot);
$graphics.CopyFromScreen(`
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.X, `
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Y, `
  0, 0, $screenshot.Size);
$cursor = [System.Windows.Forms.Cursor]::Current;
$cursorPos = [System.Windows.Forms.Cursor]::Position;
$graphics.DrawImage($cursor.Bitmap, $cursorPos.X, $cursorPos.Y);
$screenshot.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png);
$graphics.Dispose();
$screenshot.Dispose()
"]], filename)
    else
      cmd = string.format([[powershell -command "
Add-Type -AssemblyName System.Windows.Forms;
$screenshot = New-Object System.Windows.Forms.Bitmap(`
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, `
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height);
$graphics = [System.Drawing.Graphics]::FromImage($screenshot);
$graphics.CopyFromScreen(`
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.X, `
  [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Y, `
  0, 0, $screenshot.Size);
$screenshot.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png);
$graphics.Dispose();
$screenshot.Dispose()
"]], filename)
    end
  else
    print('Unsupported platform for screenshots')
    return nil
  end

  return cmd
end

-- Copy screenshot to clipboard
function M.copy_to_clipboard(filepath)
  local cmd

  if vim.fn.has('mac') == 1 then
    -- macOS: Copy to clipboard
    cmd = string.format('osascript -e \'tell application "System Events" to set the clipboard to (read (POSIX file "%s") as JPEG picture)\'', filepath)
  elseif vim.fn.has('unix') == 1 then
    -- Linux: Try different clipboard tools in order of preference
    local tools = config.get().tools.clipboard
    for _, tool in ipairs(tools) do
      if vim.fn.executable(tool) == 1 then
        if tool == 'xclip' then
          cmd = string.format('xclip -selection clipboard -t image/png "%s"', filepath)
        elseif tool == 'wl-copy' then
          cmd = string.format('wl-copy < "%s"', filepath)
        end
        break
      end
    end
  elseif vim.fn.has('win32') == 1 then
    -- Windows: PowerShell clipboard
    cmd = string.format('powershell -command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::SetImage([System.Drawing.Image]::FromFile(\'%s\'))"', filepath)
  end

  if cmd then
    vim.fn.system(cmd)
    return true
  end

  return false
end

-- Insert markdown link at cursor
function M.insert_markdown_link(filename, timestamp, is_fullscreen, custom_path)
  local markdown_path = (custom_path or config.get().markdown_path) .. filename
  local link_type = is_fullscreen and "Fullscreen" or "Screenshot"
  local markdown_link = string.format('![%s %s](%s)', link_type, timestamp, markdown_path)
  vim.api.nvim_put({markdown_link}, 'l', true, true)
end

-- Take a screenshot
function M.take_screenshot(interactive, is_fullscreen, use_global)

  local pattern = is_fullscreen and config.get().fullscreen_pattern or config.get().filename_pattern
  local filename = os.date(pattern)
  local timestamp = os.date('%Y%m%d_%H%M%S')

  -- Choose directory and markdown path based on global flag
  local screenshot_dir, markdown_path
  if use_global then
    screenshot_dir = vim.fn.expand(config.get().global_screenshot_dir)
    markdown_path = vim.fn.expand(config.get().global_screenshot_dir) .. '/'
  else
    -- For local screenshots, use directory relative to current buffer
    local buffer_dir = vim.fn.expand('%:p:h')
    screenshot_dir = buffer_dir .. '/' .. config.get().local_screenshot_dir:gsub('^%./', '')
    markdown_path = config.get().local_screenshot_dir .. '/'
  end

  local filepath = screenshot_dir .. '/' .. filename

  -- Ensure directory exists
  vim.fn.mkdir(screenshot_dir, 'p')

  -- Get platform-specific screenshot command
  local cmd = M.get_screenshot_command(filepath, interactive)

  if not cmd then
    return false
  end

  -- Execute the screenshot command
  print("Taking " .. (is_fullscreen and "fullscreen" or "screenshot") .. "...")

  -- For interactive commands, use synchronous execution to allow GUI interaction
  if interactive then
    print("Opening screenshot selection interface...")
    vim.fn.system(cmd)
    local exit_code = vim.v.shell_error

    if exit_code == 0 then
      -- Check if file was actually created (user didn't cancel)
      if vim.fn.filereadable(filepath) == 1 then
        -- Screenshot successful
        M.handle_screenshot_success(filepath, is_fullscreen, markdown_path)
        return true
      else
        print("Screenshot cancelled or no selection made")
        cleanup_empty_images_dir(screenshot_dir)
        return false
      end
    else
      print("Screenshot failed (exit code: " .. exit_code .. ")")
      return false
    end
  else
    -- For non-interactive, use synchronous execution
    vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      -- Copy to clipboard if enabled
      local clipboard_success = false
      if config.get().auto_clipboard then
        clipboard_success = M.copy_to_clipboard(filepath)
      end

      -- Insert markdown link if enabled
      if config.get().auto_insert then
        M.insert_markdown_link(filename, timestamp, is_fullscreen, markdown_path)
      end

      local msg = (is_fullscreen and 'Fullscreen' or 'Screenshot') .. ' saved: ' .. filename
      if clipboard_success then
        msg = msg .. ' (copied to clipboard)'
      end
      print(msg)
      return true
    else
      print('Screenshot cancelled or failed')
      cleanup_empty_images_dir(screenshot_dir)
      return false
    end
  end
end

-- Take interactive screenshot (local)
function M.take_screenshot_interactive()
  return M.take_screenshot(true, false, false)
end

-- Take fullscreen screenshot (local)
function M.take_fullscreen_screenshot()
  return M.take_screenshot(false, true, false)
end

-- Take interactive screenshot (global)
function M.take_screenshot_interactive_global()
  return M.take_screenshot(true, false, true)
end

-- Take fullscreen screenshot (global)
function M.take_fullscreen_screenshot_global()
  return M.take_screenshot(false, true, true)
end

-- Handle successful screenshot capture (for async operations)
function M.handle_screenshot_success(filepath, is_fullscreen, markdown_path)
  -- Copy to clipboard if enabled
  local clipboard_success = false
  if config.get().auto_clipboard then
    clipboard_success = M.copy_to_clipboard(filepath)
  end

  -- Insert markdown link if enabled
  if config.get().auto_insert then
    local filename = vim.fn.fnamemodify(filepath, ':t')
    local timestamp = os.date('%Y%m%d_%H%M%S')
    M.insert_markdown_link(filename, timestamp, is_fullscreen, markdown_path)
  end

  local msg = (is_fullscreen and 'Fullscreen' or 'Screenshot') .. ' saved: ' .. vim.fn.fnamemodify(filepath, ':t')
  if clipboard_success then
    msg = msg .. ' (copied to clipboard)'
  end
  print(msg)
end

-- Open screenshot directory
function M.open_screenshot_directory()
  local buffer_dir = vim.fn.expand('%:p:h')
  local screenshot_dir = buffer_dir .. '/' .. config.get().local_screenshot_dir:gsub('^%./', '')
  vim.fn.mkdir(screenshot_dir, 'p')  -- Ensure directory exists
  vim.cmd('edit ' .. screenshot_dir)
end

return M
