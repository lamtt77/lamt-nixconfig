return {
  -- Blink completion engine
  {
    "saghen/blink.cmp",
    dependencies = {
      "L3MON4D3/LuaSnip",
      "rafamadriz/friendly-snippets",
    },
    version = "*",
    config = function()
      local blink = require('blink.cmp')

      -- Load friendly snippets
      require("luasnip.loaders.from_vscode").lazy_load()

      blink.setup({
        keymap = {
          preset = 'default',
          ['<CR>'] = { 'select_and_accept', 'fallback' },
        },
        appearance = {
          use_nvim_cmp_as_default = false,
          nerd_font_variant = 'mono'
        },
        sources = {
          default = { 'lsp', 'path', 'snippets', 'buffer', 'copilot' },
          providers = {
            copilot = {
              name = 'copilot',
              module = 'blink-cmp-copilot',
              async = true,
            },
            dictionary = {
              module = 'blink-cmp-dictionary',
              name = 'Dict',
              min_keyword_length = 3,
              opts = {
                dictionary_files = { '/usr/share/dict/words' },
              },
            },
          },
        },
        completion = {
          menu = {
            border = 'rounded',
            winhighlight = 'Normal:Pmenu,FloatBorder:Pmenu,CursorLine:PmenuSel,Search:None',
            draw = {
              columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "source_name" } },
            },
          },
          documentation = {
            window = { border = 'rounded' },
            auto_show = true,
            auto_show_delay_ms = 500,
          },
          ghost_text = { enabled = true },
        },
        signature = { enabled = true },
      })

      -- Snippets configuration
      require('luasnip').config.set_config({
        history = true,
        updateevents = "TextChanged,TextChangedI",
        enable_autosnippets = true,
      })

      -- Manual dictionary completion trigger
      vim.keymap.set('i', '<A-d>', function()
        require('blink.cmp').show({ providers = { 'dictionary' } })
      end, { desc = 'Trigger dictionary completion' })
    end,
  },

  -- Blink Copilot integration
  {
    "giuxtaposition/blink-cmp-copilot",
  },

  -- Blink Dictionary source
  {
    "Kaiser-Yang/blink-cmp-dictionary",
  },

  -- Completion hints (mini.clue)
  {
    "echasnovski/mini.clue",
    config = function()
      require('mini.clue').setup({
        triggers = {
          -- Leader triggers
          { mode = 'n', keys = '<Leader>' },
          { mode = 'x', keys = '<Leader>' },

          -- Built-in completion
          { mode = 'i', keys = '<C-x>' },

          -- `g` key
          { mode = 'n', keys = 'g' },
          { mode = 'x', keys = 'g' },

          -- Marks
          { mode = 'n', keys = "'" },
          { mode = 'n', keys = '`' },
          { mode = 'x', keys = "'" },
          { mode = 'x', keys = '`' },

          -- Registers
          { mode = 'n', keys = '"' },
          { mode = 'x', keys = '"' },
          { mode = 'i', keys = '<C-r>' },
          { mode = 'c', keys = '<C-r>' },

          -- Window commands
          { mode = 'n', keys = '<C-w>' },

          -- `z` key
          { mode = 'n', keys = 'z' },
          { mode = 'x', keys = 'z' },
        },

        clues = {
          -- Your existing key groups
          { mode = 'n', keys = '<leader>o', desc = 'OpenCode' },
           { mode = 'n', keys = '<leader>a', desc = 'AI/Avante' },
           { mode = 'n', keys = '<leader>f', desc = 'Find/Files' },
           { mode = 'n', keys = '<leader>g', desc = 'Git' },
           { mode = 'n', keys = '<leader>h', desc = 'Hunks' },
           { mode = 'n', keys = '<leader>l', desc = 'LSP/Mason' },
           { mode = 'n', keys = '<leader>t', desc = 'Theme' },
           { mode = 'n', keys = '<leader>w', desc = 'Workspace' },
           { mode = 'n', keys = '<leader>S', desc = 'Sarch/Replace' },
           { mode = 'n', keys = '<leader>i', desc = 'Screenshot Images' },
           { mode = 'n', keys = '<leader>F', desc = 'Mini Files Float' },
           { mode = 'n', keys = '<leader>c', desc = 'Code Quality' },
           { mode = 'n', keys = '<leader>b', desc = 'Buffer Management' },
           { mode = 'n', keys = '<leader>d', desc = 'Debug/DAP' },

          -- Built-in clues
          require('mini.clue').gen_clues.builtin_completion(),
          require('mini.clue').gen_clues.g(),
          require('mini.clue').gen_clues.marks(),
          require('mini.clue').gen_clues.registers(),
          require('mini.clue').gen_clues.windows(),
          require('mini.clue').gen_clues.z(),
        },
      })
    end,
  },
}
