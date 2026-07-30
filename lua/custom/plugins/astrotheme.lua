return {
  "AstroNvim/astrotheme",
  lazy = false,
  priority = 1000,
  config = function()
    require("astrotheme").setup({
      palette = "astrodark",
      style = {
        transparent = false,
        float = true,
        neotree = true,
        border = true,
      },
    })
    vim.cmd.colorscheme("astrodark")
  end,
}
