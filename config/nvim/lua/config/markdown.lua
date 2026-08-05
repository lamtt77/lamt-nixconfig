return {
  "MeanderingProgrammer/render-markdown.nvim",
  keys = {
    {
      "<leader>tm",
      function()
        require("render-markdown").toggle()
      end,
      desc = "Toggle Render Markdown",
    },
  },
  opts = {
    file_types = { "markdown", "vimwiki", "pandoc", "markdown.inline", "markdown.math", "rmd", "org" },
    render_modes = { "n", "c", "i", "v" },
    latex = {
      enabled = false,
    },
    yaml = {
      enabled = false,
    },
  },
}