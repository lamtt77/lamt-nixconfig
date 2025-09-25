return {
  -- Catppuccin theme
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha", -- latte, frappe, macchiato, mocha
        background = {
          light = "latte",
          dark = "mocha",
        },
        transparent_background = false,
        show_end_of_buffer = false,
        term_colors = false,
        dim_inactive = {
          enabled = false,
          shade = "dark",
          percentage = 0.15,
        },
        no_italic = false,
        no_bold = false,
        no_underline = false,
        styles = {
          comments = { "italic" },
          conditionals = { "italic" },
          loops = {},
          functions = {},
          keywords = {},
          strings = {},
          variables = {},
          numbers = {},
          booleans = {},
          properties = {},
          types = {},
          operators = {},
        },
        color_overrides = {},
        custom_highlights = {
          MiniStatuslineTmux = { fg = '#89b4fa', bg = '#1e1e2e' },
        },
        integrations = {
          cmp = true,
          gitsigns = true,
          nvimtree = true,
          treesitter = true,
          notify = false,
          mini = true,  -- Enable mini integration
          telescope = true,
          lsp_trouble = false,
          lsp_saga = false,
          which_key = false,  -- Disabled since we removed which-key
          barbar = false,
          bufferline = false,
          markdown = true,
          lightspeed = false,
          ts_rainbow = false,
          hop = false,
          mason = false,
          neotest = false,
          noice = false,
          illuminate = false,
          navic = false,
          overseer = false,
          pounce = false,
          telekinesis = false,
          symbols_outline = false,
          vim_sneak = false,
          vimwiki = false,
          beacon = false,
        },
      })

      -- Set the theme
      vim.cmd.colorscheme("catppuccin")
    end,
  },
}