# Neovim Configuration

## Structure

The configuration is organized into the following modules under `lua/config/`:

### Core Modules
- **`settings.lua`** - General Neovim settings and options
- **`keymaps.lua`** - Key mappings and shortcuts
- **`lsp.lua`** - Language Server Protocol setup and configurations
- **`completion.lua`** - Completion engine and hints configuration
- **`dap.lua`** - Debug Adapter Protocol setup and configurations

### UI Modules
- **`telescope.lua`** - Fuzzy finder and search functionality
- **`file-explorer.lua`** - File browsing with Neo-tree
- **`theme.lua`** - Catppuccin theme configuration
- **`workspace.lua`** - Project detection and session management

### Feature Modules
- **`ai.lua`** - AI-assisted coding plugins and configurations
- **`git.lua`** - Git integration plugins and tools

### Utility Modules
- **`utils.lua`** - General utility functions and helpers
- **`utils/`** - Specialized utility submodules:
  - `editing.lua` - Text editing enhancements
  - `media.lua` - Media and file handling
  - `mini.lua` - Mini plugins collection
  - `search.lua` - Search and navigation tools
  - `undo.lua` - Undo tree functionality

## Main Files
- **`init.lua`** - Main configuration entry point
- **`lua/plugins.lua`** - Plugin definitions and lazy loading setup

## Usage
The modular structure allows for:
- Easier maintenance and updates
- Clear separation of concerns
- Selective loading of features
- Better code organization

Each module can be modified independently without affecting others, making the configuration more robust and easier to understand.
