return {
  -- ─── yanky.nvim ──────────────────────────────────────────────────────────
  -- Yank ring: cycle through past yanks with <C-n>/<C-p> after paste.
  -- Also makes p/P/gp/gP smarter (cursor placement, indent correction).
  -- SSH-aware: skips clipboard sync when connected via SSH.
  {
    "gbprod/yanky.nvim",
    event = "VeryLazy",
    opts = {
      system_clipboard = {
        -- Don't sync the ring with the system clipboard over SSH
        sync_with_ring = not vim.env.SSH_CONNECTION,
      },
      highlight = { timer = 150 },
    },
    keys = {
      -- Smarter paste operators (maintain cursor position / indent)
      { "p",  "<Plug>(YankyPutAfter)",               mode = { "n", "x" }, desc = "Put after (yanky)" },
      { "P",  "<Plug>(YankyPutBefore)",              mode = { "n", "x" }, desc = "Put before (yanky)" },
      { "gp", "<Plug>(YankyGPutAfter)",              mode = { "n", "x" }, desc = "GPut after (yanky)" },
      { "gP", "<Plug>(YankyGPutBefore)",             mode = { "n", "x" }, desc = "GPut before (yanky)" },
      -- Cycle through the yank ring after pasting
      { "<C-n>", "<Plug>(YankyCycleForward)",  desc = "Cycle yank forward" },
      { "<C-p>", "<Plug>(YankyCycleBackward)", desc = "Cycle yank backward" },
      -- Browse full yank history in telescope
      {
        "<leader>p",
        function()
          require("telescope").extensions.yank_history.yank_history({})
        end,
        mode = { "n", "x" },
        desc = "Yank history (telescope)",
      },
    },
  },

  -- ─── flash.nvim ──────────────────────────────────────────────────────────
  -- Lightning-fast cursor jumps: press s + 2 chars to jump anywhere on screen.
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    ---@type Flash.Config
    opts = {},
    -- stylua: ignore
    keys = {
      -- Normal / operator-pending / visual: jump to any location with 2 chars
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash jump" },
      -- Jump using Treesitter node boundaries (great for selecting functions, blocks)
      { "S", mode = { "n", "o", "x" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      -- Remote flash: apply an operator to a distant location without moving cursor
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      -- Treesitter search across multiple windows
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      -- Toggle Flash in command-line search (/foo pattern)
      { "<C-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },

  -- ─── nvim-treesitter-context ──────────────────────────────────────────────
  -- Pins the current function / class header at the top of the window so you
  -- always know what scope you're editing when scrolled deep into a file.
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      enable = true,
      max_lines = 3,          -- max sticky header height
      min_window_height = 20, -- only show when window is tall enough
      multiline_threshold = 1,
      trim_scope = "outer",
      mode = "cursor",
    },
    keys = {
      {
        "<leader>tc",
        function()
          require("treesitter-context").toggle()
        end,
        desc = "Toggle Treesitter context",
      },
      {
        "[C",
        function()
          require("treesitter-context").go_to_context(vim.v.count1)
        end,
        mode = "n",
        desc = "Jump to context (upward)",
      },
    },
  },

  -- ─── inc-rename.nvim ──────────────────────────────────────────────────────
  -- Live rename preview: shows the new name in-place as you type, instead of
  -- the plain input box from vim.lsp.buf.rename. Replaces <leader>lr.
  {
    "smjonas/inc-rename.nvim",
    cmd = "IncRename",
    config = function()
      require("inc_rename").setup()
    end,
    keys = {
      {
        "<leader>lr",
        function()
          return ":IncRename " .. vim.fn.expand("<cword>")
        end,
        expr = true,
        desc = "Rename symbol (live preview)",
      },
    },
  },
}
