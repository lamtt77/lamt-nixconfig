-- Formatting configuration
return {
  -- Conform for formatting
  {
     "stevearc/conform.nvim",
     event = "VeryLazy",
    config = function()
      local conform = require("conform")

      conform.setup({
         formatters_by_ft = {
           lua = { "stylua" },
           python = { "ruff_format" },
           javascript = { "prettier" },
           typescript = { "prettier" },
           javascriptreact = { "prettier" },
           typescriptreact = { "prettier" },
           json = { "prettier" },
           yaml = { "prettier" },
           markdown = { "prettier" },
           nix = { "alejandra" },
           c = { "clang_format" },
           cpp = { "clang_format" },
         },
         format_on_save = function(bufnr)
           if vim.bo[bufnr].filetype == "nix" then
             return false
           end
           return { lsp_fallback = true }
         end,
      })

       -- Keymaps for formatting
       vim.keymap.set({ "n", "v" }, "<leader>mp", function()
         print("Formatting with conform")
         conform.format({
           lsp_fallback = true,
           async = false,
           timeout_ms = 1000,
         })
       end, { desc = "Format file or range (in visual mode)" })
    end,
  },
}
