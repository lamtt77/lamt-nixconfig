return {
  -- Search and replace (wgrep-like)
  {
    "nvim-pack/nvim-spectre",
    cmd = "Spectre",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>S", "<cmd>lua require('spectre').open()<CR>", desc = "Open Spectre search/replace" },
      { "<leader>sw", "<cmd>lua require('spectre').open_visual({select_word=true})<CR>", desc = "Search current word" },
      { "<leader>s", "<esc><cmd>lua require('spectre').open_visual()<CR>", mode = "v", desc = "Search current selection" },
    },
    config = function()
      require('spectre').setup({
        live_update = true,
        is_insert_mode = true,
        highlight = {
          ui = "String",
          search = "DiffChange",
          replace = "DiffDelete"
        },
        mapping = {
          ['toggle_line'] = {
            map = "dd",
            cmd = "<cmd>lua require('spectre').toggle_line()<CR>",
            desc = "toggle current item"
          },
          ['enter_file'] = {
            map = "<cr>",
            cmd = "<cmd>lua require('spectre.actions').select_entry()<CR>",
            desc = "goto current file"
          },
          ['send_to_qf'] = {
            map = "<C-q>",
            cmd = "<cmd>lua require('spectre.actions').send_to_qf()<CR>",
            desc = "send all item to quickfix"
          },
          ['show_option_menu'] = {
            map = "<C-o>",
            cmd = "<cmd>lua require('spectre').show_options()<CR>",
            desc = "show option"
          },
          ['run_replace'] = {
            map = "<C-r>",
            cmd = "<cmd>lua require('spectre').run_replace()<CR>",
            desc = "replace all"
          },
          ['change_view_mode'] = {
            map = "<C-v>",
            cmd = "<cmd>lua require('spectre').change_view()<CR>",
            desc = "change result view mode"
          },
        },
      })
    end,
  },
}
