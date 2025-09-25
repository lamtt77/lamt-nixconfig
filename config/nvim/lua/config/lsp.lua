-- LSP Configuration
return {
  {
    "neovim/nvim-lspconfig", version = "*",
    config = function()
      -- Diagnostic configuration
      vim.diagnostic.config({
        virtual_text = true,
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
      })

      -- Diagnostic signs
      local signs = { Error = "❌", Warn = "⚠️", Hint = "💡", Info = "ℹ️" }
      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end

      -- LSP keybindings
      vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { noremap = true, silent = true, desc = 'Go to declaration' })
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { noremap = true, silent = true, desc = 'Go to definition' })
      vim.keymap.set('n', 'K', vim.lsp.buf.hover, { noremap = true, silent = true, desc = 'Hover documentation' })
      vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { noremap = true, silent = true, desc = 'Go to implementation' })
      vim.keymap.set('n', '<leader>k', vim.lsp.buf.signature_help, { noremap = true, silent = true, desc = 'Signature help' })

      vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, { noremap = true, silent = true, desc = 'Type definition' })
      vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { noremap = true, silent = true, desc = 'Rename symbol' })
      vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { noremap = true, silent = true, desc = 'Code action' })
      -- Changed from 'gr' to '<leader>lr' to avoid overlap
      vim.keymap.set('n', '<leader>lr', vim.lsp.buf.references, { noremap = true, silent = true, desc = 'LSP references' })
      vim.keymap.set('n', '<leader>fmt', function()
        vim.lsp.buf.format({ async = true })
      end, { noremap = true, silent = true, desc = 'Format buffer' })
    end,
  },

  -- Mason LSP server manager
  {
    "williamboman/mason.nvim",
     config = function()
       require("mason").setup({
         ui = {
           icons = {
             package_installed = "✓",
             package_pending = "➜",
             package_uninstalled = "✗"
           }
         },
          ensure_installed = {
            -- DAP debuggers
            "debugpy",        -- Python
            "delve",          -- Go
            "codelldb",       -- Rust (alternative to lldb-vscode)
            "js-debug-adapter", -- JavaScript/TypeScript
            "lldb-vscode",    -- C/C++/Swift/Zig (LLDB-based debugger)
         }
       })
     end,
   },

   -- Mason LSP configuration bridge
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",      -- Lua
          "ts_ls",       -- TypeScript/JavaScript
          "gopls",       -- Go
          "pyright",     -- Python
          "rust_analyzer", -- Rust
          "nil_ls",      -- Nix
        },
        automatic_installation = true,
        handlers = {
          -- Default handler for all servers
          function(server_name)
            vim.lsp.config[server_name] = {
              capabilities = vim.lsp.protocol.make_client_capabilities(),
            }
            vim.lsp.enable(server_name)
          end,

          -- Special handling for lua_ls
          ["lua_ls"] = function()
            vim.lsp.config.lua_ls = {
              capabilities = vim.lsp.protocol.make_client_capabilities(),
              settings = {
                Lua = {
                  runtime = {
                    version = 'LuaJIT',
                  },
                  diagnostics = {
                    globals = {'vim'},
                  },
                  workspace = {
                    library = vim.api.nvim_get_runtime_file("", true),
                  },
                  telemetry = {
                    enable = false,
                  },
                 },
                }
              }
            vim.lsp.enable('lua_ls')
          end,

          -- Special handling for nil_ls
          ["nil_ls"] = function()
            vim.lsp.config.nil_ls = {
              capabilities = vim.lsp.protocol.make_client_capabilities(),
              settings = {
                ['nil'] = {
                  formatting = {
                    command = { "alejandra" },
                  },
                },
              },
            }
            vim.lsp.enable('nil_ls')
          end,
        },
      })
    end,
  },

  -- Mason key mappings
  {
    "williamboman/mason.nvim",
    keys = {
      { "<leader>lm", "<cmd>Mason<CR>", desc = "Mason: Open LSP manager" },
      { "<leader>li", "<cmd>MasonInstall<CR>", desc = "Mason: Install LSP server" },
      { "<leader>lu", "<cmd>MasonUninstall<CR>", desc = "Mason: Uninstall LSP server" },
      { "<leader>ll", "<cmd>MasonLog<CR>", desc = "Mason: Show logs" },
    },
  },

  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    event = "BufReadPre",
    build = ":TSUpdate",
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = { "lua", "vim", "vimdoc", "python", "javascript", "typescript", "nix" },
        highlight = { enable = true },
        indent = { enable = true },
        modules = {},
        sync_install = false,
        ignore_install = {},
        auto_install = false,
      })
    end,
  },

  -- Rust tools (LSP)
  {
    "simrat39/rust-tools.nvim",
    config = function()
      local rt = require("rust-tools")
      rt.setup({
        server = {
          on_attach = function(_, bufnr)
            -- Hover actions
            vim.keymap.set("n", "<C-space>", rt.hover_actions.hover_actions, { buffer = bufnr })
            -- Code action groups
            vim.keymap.set("n", "<Leader>a", rt.code_action_group.code_action_group, { buffer = bufnr })
          end,
        },
        -- Disable rust-tools DAP adapter to avoid conflicts with mason codelldb
        dap = {
          adapter = false,
        },
      })
    end,
  },
}
