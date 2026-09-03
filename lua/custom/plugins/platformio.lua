-- PlatformIO (embedded / Arduino / ESP32) wrapper.
-- Requires the PlatformIO Core CLI (`pio`) on $PATH: https://docs.platformio.org/en/latest/core/installation/
return {
	{
		"akinsho/toggleterm.nvim",
		version = "*",
		cmd = { "ToggleTerm", "TermExec" },
		opts = {},
	},

	{
		"anurag3301/nvim-platformio.lua",
		dependencies = {
			"akinsho/toggleterm.nvim",
			"nvim-telescope/telescope.nvim",
			"nvim-telescope/telescope-ui-select.nvim",
			"nvim-lua/plenary.nvim",
			"folke/which-key.nvim",
			"nvim-treesitter/nvim-treesitter",
		},
		cmd = {
			"Pioinit",
			"PioLSP",
			"Piorun",
			"Piomon",
			"Piolsserial",
			"Piolib",
			"Piocmdh",
			"Piocmdf",
			"Piodebug",
			"PioTermList",
		},
		keys = {
			-- No rhs: lazy loads the plugin, then replays the key so the
			-- plugin's own which-key menu tree takes over.
			{ "<leader>Pm", desc = "PlatformIO [M]enu" },

			{ "<leader>Pi", "<cmd>Pioinit<cr>", desc = "[I]nit project" },
			{ "<leader>Pb", "<cmd>Piocmdf run<cr>", desc = "[B]uild" },
			{ "<leader>Pu", "<cmd>Piocmdf run -t upload<cr>", desc = "[U]pload" },
			-- Horizontal like the plain monitor: it stays open streaming serial output.
			{ "<leader>PU", "<cmd>Piocmdh run -t upload -t monitor<cr>", desc = "[U]pload + monitor" },
			{ "<leader>Ps", "<cmd>Piocmdh run -t monitor<cr>", desc = "[S]erial monitor" },
			{ "<leader>PS", "<cmd>Piolsserial<cr>", desc = "List [S]erial devices" },
			{ "<leader>Pc", "<cmd>Piocmdf run -t clean<cr>", desc = "[C]lean" },
			{ "<leader>PC", "<cmd>Piocmdf run -t fullclean<cr>", desc = "Full [C]lean" },
			{ "<leader>Pd", "<cmd>Piocmdf device list<cr>", desc = "[D]evice list" },
			{ "<leader>PD", "<cmd>Piodebug<cr>", desc = "[D]ebug (gdb)" },
			{ "<leader>Pt", "<cmd>Piocmdf test<cr>", desc = "[T]est" },
			{ "<leader>Pk", "<cmd>Piocmdf check<cr>", desc = "Chec[k] (static analysis)" },
			-- `:Piolib` needs a search keyword, so leave the cmdline open.
			{ "<leader>Pl", ":Piolib ", desc = "[L]ibrary install", silent = false },
			{ "<leader>PT", "<cmd>PioTermList<cr>", desc = "[T]erminal list" },
			{ "<leader>Pp", "<cmd>Piocmdf<cr>", desc = "[P]io CLI terminal" },
			{ "<leader>PL", "<cmd>PioLSP<cr>", desc = "Regenerate [L]SP config" },
		},
		config = function()
			require("platformio").setup({
				-- clangd is already installed via Mason; ccls is not, and the
				-- `ccls` source only means "derive flags from the .ccls file
				-- pio generates" -- it does not need the ccls binary.
				lsp = "clangd",
				clangd_source = "ccls",
				picker_backend = "auto",
				menu_key = "<leader>Pm",
				menu_name = "PlatformIO",
				debug = false,
			})
		end,
	},
}
