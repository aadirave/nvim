local M = {
	"antigravity",
	-- Verification comment: remote-expr diff preview is active
	dir = vim.fn.stdpath("config"),
	lazy = false,
	priority = 100,
}

local function get_agy_binary()
	if vim.fn.executable("agy") == 1 then
		return "agy"
	elseif vim.fn.executable("/opt/homebrew/bin/agy") == 1 then
		return "/opt/homebrew/bin/agy"
	elseif vim.fn.executable("/usr/local/bin/agy") == 1 then
		return "/usr/local/bin/agy"
	end
	return "agy"
end

local config = {
	layout = "split", -- "float" or "split"
	split_width = 0.35, -- 35% of editor width
	float_width = 0.85,
	float_height = 0.85,
	border = "rounded",
}

local active_win = nil
local active_buf = nil

local function open_terminal(args)
	-- Focus window if already open and valid
	if active_win and vim.api.nvim_win_is_valid(active_win) then
		vim.api.nvim_set_current_win(active_win)
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local win

	if config.layout == "split" then
		vim.cmd("botright vsplit")
		win = vim.api.nvim_get_current_win()
		local width = math.floor(vim.o.columns * config.split_width)
		vim.cmd("vertical resize " .. width)
		vim.api.nvim_win_set_buf(win, buf)
	else
		local width = math.floor(vim.o.columns * config.float_width)
		local height = math.floor(vim.o.lines * config.float_height)
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)
		win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = config.border,
			title = " Antigravity AI Agent ",
			title_pos = "center",
		})
	end

	active_win = win
	active_buf = buf

	local binary = get_agy_binary()
	local cmd = { binary }
	if args then
		for _, arg in ipairs(args) do
			table.insert(cmd, arg)
		end
	end

	vim.fn.termopen(cmd, {
		on_exit = function(_, _, _)
			if win and vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
			if buf and vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
			active_win = nil
			active_buf = nil
		end,
	})

	vim.cmd("startinsert")

	-- Clean window appearance
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].signcolumn = "no"

	-- Allow hiding/closing window with Alt-q
	vim.keymap.set("t", "<A-q>", "<C-\\><C-n><Cmd>close<CR>", { buffer = buf, desc = "Close Antigravity Window" })

	-- Allow window navigation from terminal mode (Vim/Tmux integrated)
	vim.keymap.set("t", "<C-h>", "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>", { buffer = buf, desc = "Move focus to left window" })
	vim.keymap.set("t", "<C-j>", "<C-\\><C-n><cmd>TmuxNavigateDown<cr>", { buffer = buf, desc = "Move focus to lower window" })
	vim.keymap.set("t", "<C-k>", "<C-\\><C-n><cmd>TmuxNavigateUp<cr>", { buffer = buf, desc = "Move focus to upper window" })
	vim.keymap.set("t", "<C-l>", "<C-\\><C-n><cmd>TmuxNavigateRight<cr>", { buffer = buf, desc = "Move focus to right window" })
end

local function toggle_layout()
	if config.layout == "split" then
		config.layout = "float"
		vim.notify("Antigravity layout set to floating window", vim.log.levels.INFO)
	else
		config.layout = "split"
		vim.notify("Antigravity layout set to side-by-side vertical split", vim.log.levels.INFO)
	end
end

local function toggle_diff()
	local found_diff_win = nil
	local current_tab = vim.api.nvim_get_current_tabpage()
	local wins = vim.api.nvim_tabpage_list_wins(current_tab)

	for _, w in ipairs(wins) do
		if vim.wo[w].diff then
			found_diff_win = w
			break
		end
	end

	if found_diff_win then
		vim.cmd("diffoff!")
		pcall(vim.api.nvim_win_close, found_diff_win, true)
	else
		local gitsigns_status, gitsigns = pcall(require, "gitsigns")
		if gitsigns_status then
			gitsigns.diffthis()
		else
			vim.cmd("vnew | r !git show HEAD:#")
			vim.cmd("setlocal buftype=nofile bufhidden=wipe noswapfile filetype=" .. vim.bo.filetype)
			vim.cmd("diffthis")
			vim.cmd("wincmd p")
			vim.cmd("diffthis")
		end
	end
end

local function get_file_info()
	local filepath = vim.api.nvim_buf_get_name(0)
	local relative_path = vim.fn.fnamemodify(filepath, ":.")
	local filetype = vim.bo.filetype
	return relative_path, filetype
end

M.config = function()
	-- Save servername for the preview script to use if environment variable is missing
	local servername = vim.v.servername
	if servername then
		local f = io.open("/tmp/antigravity_nvim_socket", "w")
		if f then
			f:write(servername)
			f:close()
		end
	end

	-- Expose global functions for safe remote RPC invocation via remote-expr (prevents keyboard-injection issues in terminal mode)
	_G.AntigravityShowProposedDiff = function(target_file, temp_file)
		-- Ensure we open target_file in a main code window (not the terminal pane window)
		local current_tab = vim.api.nvim_get_current_tabpage()
		local wins = vim.api.nvim_tabpage_list_wins(current_tab)
		local main_win = nil
		for _, w in ipairs(wins) do
			local buf = vim.api.nvim_win_get_buf(w)
			local buftype = vim.bo[buf].buftype
			if buftype == "" or buftype == "acwrite" then
				main_win = w
				break
			end
		end

		if main_win then
			vim.api.nvim_set_current_win(main_win)
		end

		-- Open target_file in current window
		vim.cmd("edit " .. vim.fn.fnameescape(target_file))

		-- Close any existing diffs to clean up
		vim.cmd("diffoff!")
		for _, w in ipairs(wins) do
			local buf = vim.api.nvim_win_get_buf(w)
			local bufname = vim.api.nvim_buf_get_name(buf)
			if bufname:match("antigravity_diff") or bufname:match("antigravity_proposed") then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end

		-- Open vertical split with the temp_file and start diff mode
		vim.cmd("vsplit " .. vim.fn.fnameescape(temp_file))
		local temp_buf = vim.api.nvim_get_current_buf()
		vim.bo[temp_buf].buftype = "nofile"
		vim.bo[temp_buf].bufhidden = "wipe"
		vim.bo[temp_buf].swapfile = false
		vim.bo[temp_buf].modifiable = false

		-- Diff both windows
		vim.cmd("diffthis")
		vim.cmd("wincmd p") -- go back to main window
		vim.cmd("diffthis")
	end

	_G.AntigravityCloseProposedDiff = function()
		-- Turn off diff
		vim.cmd("diffoff!")
		-- Find any open window with temporary buffer and close it
		local current_tab = vim.api.nvim_get_current_tabpage()
		local wins = vim.api.nvim_tabpage_list_wins(current_tab)
		for _, w in ipairs(wins) do
			local buf = vim.api.nvim_win_get_buf(w)
			local bufname = vim.api.nvim_buf_get_name(buf)
			if bufname:match("antigravity_diff") or bufname:match("antigravity_proposed") or vim.bo[buf].buftype == "nofile" then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end
	end

	-- Define user commands
	vim.api.nvim_create_user_command("AntigravityShowProposedDiff", function(opts)
		local args = vim.split(opts.args, " ")
		if #args < 2 then return end
		_G.AntigravityShowProposedDiff(args[1], args[2])
	end, { nargs = "*" })

	vim.api.nvim_create_user_command("AntigravityCloseProposedDiff", function()
		_G.AntigravityCloseProposedDiff()
	end, {})

	vim.api.nvim_create_user_command("AntigravityChat", function()
		open_terminal()
	end, {})

	vim.api.nvim_create_user_command("AntigravityContinue", function()
		open_terminal({ "--continue" })
	end, {})

	vim.api.nvim_create_user_command("AntigravityToggleLayout", function()
		toggle_layout()
	end, {})

	vim.api.nvim_create_user_command("AntigravityDiff", function()
		toggle_diff()
	end, {})

	vim.api.nvim_create_user_command("AntigravityAsk", function()
		vim.ui.input({ prompt = "Ask Antigravity: " }, function(input)
			if not input or input == "" then
				return
			end
			open_terminal({ "--prompt-interactive", input })
		end)
	end, {})

	vim.api.nvim_create_user_command("AntigravityExplain", function(opts)
		local relative_path, filetype = get_file_info()
		local lines
		if opts.range == 2 then
			lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		else
			lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		end
		local code = table.concat(lines, "\n")
		local prompt = string.format(
			"Please explain the following %s code (file: `%s`):\n\n```%s\n%s\n```",
			filetype,
			relative_path,
			filetype,
			code
		)
		open_terminal({ "--prompt-interactive", prompt })
	end, { range = true })

	vim.api.nvim_create_user_command("AntigravityFix", function()
		local relative_path, filetype = get_file_info()
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local code = table.concat(lines, "\n")

		local diags = vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
		if #diags == 0 then
			diags = vim.diagnostic.get(0)
		end

		local diag_msg = ""
		if #diags > 0 then
			diag_msg = "Here are the diagnostics/compiler errors reported:\n"
			for _, d in ipairs(diags) do
				diag_msg = diag_msg .. string.format("- Line %d: %s\n", d.lnum + 1, d.message)
			end
		else
			diag_msg = "Please review the code for any bugs, style issues, or improvements."
		end

		local prompt = string.format(
			"There is an issue in my %s code (file: `%s`). %s\n\nHere is the code:\n\n```%s\n%s\n```\n\nPlease help me fix it.",
			filetype,
			relative_path,
			diag_msg,
			filetype,
			code
		)
		open_terminal({ "--prompt-interactive", prompt })
	end, {})

	vim.api.nvim_create_user_command("AntigravityRefactor", function(opts)
		local relative_path, filetype = get_file_info()
		local start_line = opts.line1
		local end_line = opts.line2
		local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
		local code = table.concat(lines, "\n")

		vim.ui.input({ prompt = "Refactor Instruction: " }, function(input)
			if not input or input == "" then
				return
			end
			local prompt = string.format(
				"Please refactor the following code block in %s (file: `%s`, lines %d-%d) according to this instruction: \"%s\"\n\nCode:\n\n```%s\n%s\n```",
				filetype,
				relative_path,
				start_line,
				end_line,
				input,
				filetype,
				code
			)
			open_terminal({ "--prompt-interactive", prompt })
		end)
	end, { range = true })

	-- Register keymaps
	local wk_status, wk = pcall(require, "which-key")
	if wk_status then
		wk.add({
			{ "<leader>a", group = "[A]ntigravity", mode = { "n", "x" } },
			{ "<leader>ac", "<cmd>AntigravityChat<cr>", desc = "Chat" },
			{ "<leader>aC", "<cmd>AntigravityContinue<cr>", desc = "Continue Last Chat" },
			{ "<leader>aa", "<cmd>AntigravityAsk<cr>", desc = "Ask Prompt" },
			{ "<leader>ae", "<cmd>AntigravityExplain<cr>", desc = "Explain Code", mode = { "n", "x" } },
			{ "<leader>af", "<cmd>AntigravityFix<cr>", desc = "Fix Code / Diagnostics" },
			{ "<leader>ar", "<cmd>AntigravityRefactor<cr>", desc = "Refactor Code", mode = { "n", "x" } },
			{ "<leader>al", "<cmd>AntigravityToggleLayout<cr>", desc = "Toggle Layout (Float/Split)" },
			{ "<leader>ad", "<cmd>AntigravityDiff<cr>", desc = "Toggle Live Diff (Claude-style)" },
		})
	else
		local map = function(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "Antigravity: " .. desc })
		end
		map("n", "<leader>ac", "<cmd>AntigravityChat<cr>", "Chat")
		map("n", "<leader>aC", "<cmd>AntigravityContinue<cr>", "Continue Last Chat")
		map("n", "<leader>aa", "<cmd>AntigravityAsk<cr>", "Ask Prompt")
		map({ "n", "x" }, "<leader>ae", "<cmd>AntigravityExplain<cr>", "Explain Code")
		map("n", "<leader>af", "<cmd>AntigravityFix<cr>", "Fix Code / Diagnostics")
		map({ "n", "x" }, "<leader>ar", "<cmd>AntigravityRefactor<cr>", "Refactor Code")
		map("n", "<leader>al", "<cmd>AntigravityToggleLayout<cr>", "Toggle Layout (Float/Split)")
		map("n", "<leader>ad", "<cmd>AntigravityDiff<cr>", "Toggle Live Diff (Claude-style)")
	end
end

return M
