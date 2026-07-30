return {
  "windwp/nvim-autopairs",
  event = "InsertEnter",
  config = function()
    require("nvim-autopairs").setup()

    local Rule = require("nvim-autopairs.rule")
    local npairs = require("nvim-autopairs")
    local ts_conds = require("nvim-autopairs.ts-conds")

    npairs.add_rule(Rule("$", "$", { "typ", "typst" }))
    npairs.add_rule(Rule("*", "*", { "typ", "typst" }):with_pair(ts_conds.is_not_ts_node({ "math" })))
    npairs.add_rule(Rule("_", "_", { "typ", "typst" }):with_pair(ts_conds.is_not_ts_node({ "math" })))
  end,
}
