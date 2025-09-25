# screenshot.nvim

A cross-platform screenshot plugin for Neovim with automatic markdown link insertion and clipboard integration.

## Features

- **Cross-platform support**: Works on macOS, Linux, and Windows
- **Automatic markdown insertion**: Inserts screenshot links in markdown files
- **Clipboard integration**: Automatically copies screenshots to system clipboard
- **Interactive and fullscreen screenshots**: Support for both selection and full screen capture
- **Inline image display**: Integrates with image.nvim for inline image preview
- **Configurable**: Customizable paths, keymaps, and behavior

## Requirements

### Dependencies
- **image.nvim**: For inline image display in markdown files
- **ImageMagick**: Required by image.nvim for image processing

### NixOS
For NixOS users, add these packages to your `home.packages` or system packages:

```nix
# In your home.nix or configuration.nix
{
  home.packages = with pkgs; [
    # Screenshot tools
    maim        # Recommended screenshot tool
    scrot       # Alternative screenshot tool
    flameshot   # GUI screenshot tool
    xclip       # X11 clipboard (for Xorg)
    wl-clipboard # Wayland clipboard (for Wayland)

    # Image display dependencies
    imagemagick # Required by image.nvim
    kitty       # Terminal with graphics protocol support
  ];
}
```

Or if using home-manager:
```nix
# In your home.nix
{
  home.packages = [
    pkgs.maim
    pkgs.scrot
    pkgs.flameshot
    pkgs.xclip
    pkgs.wl-clipboard
    pkgs.imagemagick
    pkgs.kitty
  ];
}
```

### macOS
- Built-in `screencapture` command (native screenshot tool)

### Linux (non-NixOS)
- `maim` (recommended)
- `scrot` (alternative)
- `flameshot` (alternative)
- `xclip` (X11) or `wl-copy` (Wayland) for clipboard

### Windows
- PowerShell (built-in)

## Installation

### With lazy.nvim

```lua
-- First, ensure image.nvim is installed for inline image display
{
  "3rd/image.nvim",
  build = false, -- Disable luarocks build (use CLI ImageMagick)
  config = function()
    require('image').setup({
      backend = "kitty",
      processor = "magick_cli", -- Works with Nix ImageMagick
      integrations = {
        markdown = {
          enabled = true,
          filetypes = { "markdown", "vimwiki" },
        },
      },
    })
  end,
},

-- Then install the screenshot plugin
{
  dir = "path/to/screenshot.nvim",
  config = function()
    require("screenshot").setup({
      -- Optional configuration
      local_screenshot_dir = "./images",              -- Local screenshots directory (relative to current buffer)
      global_screenshot_dir = "~/.local/nvim_screenshots", -- Global screenshots directory
      keymaps = {
        interactive = "<leader>ss",                   -- Local interactive
        fullscreen = "<leader>sf",                    -- Local fullscreen
        interactive_global = "<leader>sS",            -- Global interactive
        fullscreen_global = "<leader>sF",             -- Global fullscreen
        check = "<leader>sc",
        directory = "<leader>sd",
        toggle_images = "<leader>ti",
      },
      auto_clipboard = true,
      auto_insert = true,
    })
   end,
}
```

### NixOS Notes
- The `build = false` option for image.nvim prevents luarocks issues on NixOS
- Use `processor = "magick_cli"` to work with Nix-installed ImageMagick
- Ensure Kitty is your default terminal for best image display performance
- For Wayland users, `wl-clipboard` provides better clipboard integration than `xclip`
- If using home-manager, the packages are already configured in your `home.packages` list

## Configuration

### Default Configuration

```lua
{
  local_screenshot_dir = "./images",              -- Local screenshots directory
  global_screenshot_dir = "~/.local/nvim_screenshots", -- Global screenshots directory
  keymaps = {
    interactive = "<leader>ss",                  -- Take interactive screenshot
    fullscreen = "<leader>sf",                   -- Take fullscreen screenshot
    check = "<leader>sc",                        -- Check tool availability
    directory = "<leader>sd",                    -- Open screenshot directory
    toggle_images = "<leader>ti",                -- Toggle inline image display
  },
  tools = {
    linux = { "maim", "scrot", "flameshot" },    -- Linux tool preference order
    clipboard = { "xclip", "wl-copy" },          -- Clipboard tool preference order
  },
  auto_clipboard = true,                         -- Auto-copy to clipboard
  auto_insert = true,                            -- Auto-insert markdown links
  filename_pattern = "screenshot_%Y%m%d_%H%M%S.png",
  fullscreen_pattern = "fullscreen_%Y%m%d_%H%M%S.png",
}
```

## Usage

### Key Mappings

**Local Screenshots** (saved to `./images/` relative to current buffer's directory):
- `<leader>ss` - Take interactive screenshot (select area)
- `<leader>sf` - Take fullscreen screenshot

**Global Screenshots** (saved to `~/.local/nvim_screenshots/` absolute path):
- `<leader>sS` - Take interactive screenshot (global)
- `<leader>sF` - Take fullscreen screenshot (global)

**Utilities**:
- `<leader>sc` - Check screenshot tool availability
- `<leader>sd` - Open screenshot directory
- `<leader>ti` - Toggle inline image display (requires image.nvim plugin)

### Commands

- `:ImageStatus` - Show comprehensive status of image integration
- `:ScreenshotCheck` - Check availability of screenshot tools

## Dependencies

This plugin works best with:

- [image.nvim](https://github.com/3rd/image.nvim) - For inline image display (auto-display enabled for markdown files, cleared for others)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - Required for file operations

## Platform-specific Setup

### Linux Installation

```bash
# Ubuntu/Debian
sudo apt install maim xclip

# Arch Linux
sudo pacman -S maim xclip

# Fedora
sudo dnf install maim xclip

# Alternative tools
sudo apt install scrot
sudo snap install flameshot
```

### macOS

No additional setup required - uses built-in `screencapture`.

### Windows

No additional setup required - uses PowerShell.

## License

This plugin is released under the MIT License.
