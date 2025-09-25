return {
  -- Project management
  {
    "ahmedkhalf/project.nvim",
    config = function()
      require("project_nvim").setup({
        -- Project detection
        detection_methods = { "lsp", "pattern" },
        patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json", "flake.nix" },

        -- Don't show hidden files
        show_hidden = false,

        -- Silent directory changes
        silent_chdir = true,

        -- Exclude directories
        exclude_dirs = { "~/node_modules/**" },
      })
    end,
  },

  -- Session management
  {
    "rmagatti/auto-session",
    lazy = false,
    opts = {
      -- auto_save_enabled = false,
      -- auto_restore_enabled = false,
      suppressed_dirs = { "~/", "~/Projects", "~/Downloads", "/" },
      session_lens = {
        picker = "telescope",
        mappings = {
          delete_session = { "i", "<C-d>" },
          alternate_session = { "i", "<C-s>" },
          copy_session = { "i", "<C-y>" },
        },
      },
    },
    keys = {
      { "<leader>wp", "<cmd>AutoSession search<CR>", desc = "Workspace Session search" },
      { "<leader>ws", "<cmd>AutoSession save<CR>", desc = "Workspace Save session" },
      { "<leader>wl", "<cmd>AutoSession restore<CR>", desc = "Workspace load session" },
      { "<leader>wd", "<cmd>AutoSession delete<CR>", desc = "Workspace Delete session" },
      { "<leader>ww", function() require('telescope').extensions.projects.projects() end, desc = 'Find projects' },
      { "<leader>wr", function() require('telescope').extensions.projects.projects({ display_type = 'minimal' }) end, desc = 'Find recent workspaces' },
    },
  },
}
