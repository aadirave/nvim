local M = {
	"claude-code",
	dir = vim.fn.stdpath("config"),
	lazy = false,
	priority = 100,
}

local function get_claude_binary()
	local candidates = {
		"claude",
		vim.fn.expand("~/.claude/local/claude"),
		"/opt/homebrew/bin/claude",
		"/usr/local/bin/claude",
	}
	for _, bin in ipairs(candidates) do
		if vim.fn.executable(bin) == 1 then
			return bin
		end
	end
	return "claude"
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
			title = " Claude Code ",
			title_pos = "center",
		})
	end

	active_win = win
	active_buf = buf

	local binary = get_claude_binary()
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
	vim.keymap.set("t", "<A-q>", "<C-\\><C-n><Cmd>close<CR>", { buffer = buf, desc = "Close Claude Window" })

	-- Allow window navigation from terminal mode
	vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", { buffer = buf, desc = "Move focus to left window" })
	vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", { buffer = buf, desc = "Move focus to lower window" })
	vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", { buffer = buf, desc = "Move focus to upper window" })
	vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", { buffer = buf, desc = "Move focus to right window" })
end

local function toggle_layout()
	if config.layout == "split" then
		config.layout = "float"
		vim.notify("Claude layout set to floating window", vim.log.levels.INFO)
	else
		config.layout = "split"
		vim.notify("Claude layout set to side-by-side vertical split", vim.log.levels.INFO)
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
	-- Save servername so the diff-preview hook can find this instance if $NVIM is missing
	local servername = vim.v.servername
	if servername then
		local f = io.open("/tmp/claude_nvim_socket", "w")
		if f then
			f:write(servername)
			f:close()
		end
	end

	-- Tracks the windows we create for a proposed-diff so we can tear them down
	-- again and restore the exact previous layout.
	local diff_state = {
		before_win = nil,
		after_win = nil,
		created_before = false,
		host_win = nil, -- editor window we reused for the "before" side (if any)
		host_prev_buf = nil, -- buffer that host_win showed before we hijacked it
		saved_sizes = nil, -- { [win_id] = { width, height } } snapshot to restore
	}

	-- True only when we actually have a Claude proposed-diff on screen.
	local function diff_is_open()
		if diff_state.after_win and vim.api.nvim_win_is_valid(diff_state.after_win) then
			return true
		end
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
			if name:match("claude_diff") or name:match("claude_proposed") then
				return true
			end
		end
		return false
	end

	-- Run window juggling with redraws batched so the layout appears in one
	-- paint instead of flickering through intermediate states.
	local function without_flicker(fn)
		local save_lz = vim.o.lazyredraw
		vim.o.lazyredraw = true
		local ok, err = pcall(fn)
		vim.o.lazyredraw = save_lz
		vim.cmd("redraw")
		if not ok then
			error(err)
		end
	end

	-- Restore each snapshotted window to its saved size. Two passes because
	-- resizing one window nudges its neighbours; the second pass converges. Run
	-- this only while 'equalalways' sits at its normal value -- toggling that
	-- option re-equalizes and would undo the restore.
	local function restore_sizes(skip_win)
		if not diff_state.saved_sizes then
			return
		end
		for _ = 1, 2 do
			for w, wh in pairs(diff_state.saved_sizes) do
				if w ~= skip_win and vim.api.nvim_win_is_valid(w) then
					pcall(vim.api.nvim_win_set_width, w, wh[1])
					pcall(vim.api.nvim_win_set_height, w, wh[2])
				end
			end
		end
	end

	local function close_proposed_diff()
		-- No-op if there is no Claude diff open, so a stray post-hook can never
		-- disturb the user's own diffs / layout.
		if not diff_is_open() then
			return
		end

		without_flicker(function()
			-- Turn diff mode off only on the windows we touched.
			for _, w in ipairs({ diff_state.before_win, diff_state.after_win }) do
				if w and vim.api.nvim_win_is_valid(w) then
					vim.api.nvim_win_call(w, function()
						vim.cmd("diffoff")
					end)
				end
			end

			-- Close the proposed ("after") window we opened.
			if diff_state.after_win and vim.api.nvim_win_is_valid(diff_state.after_win) then
				pcall(vim.api.nvim_win_close, diff_state.after_win, true)
			end
			-- Close the "before" window only if we created it ourselves. If we
			-- reused an existing editor window, restore the buffer it had before.
			if diff_state.created_before then
				if diff_state.before_win and vim.api.nvim_win_is_valid(diff_state.before_win) then
					pcall(vim.api.nvim_win_close, diff_state.before_win, true)
				end
			elseif diff_state.host_win and vim.api.nvim_win_is_valid(diff_state.host_win) and diff_state.host_prev_buf and vim.api.nvim_buf_is_valid(diff_state.host_prev_buf) then
				pcall(vim.api.nvim_win_set_buf, diff_state.host_win, diff_state.host_prev_buf)
			end

			-- Safety net: close any lingering proposed buffers by name.
			for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
				if name:match("claude_diff") or name:match("claude_proposed") then
					pcall(vim.api.nvim_win_close, w, true)
				end
			end

			-- Restore the exact window sizes we started with (equalalways is at
			-- its normal value here, so these stick).
			restore_sizes(nil)
		end)

		diff_state.before_win, diff_state.after_win, diff_state.created_before = nil, nil, false
		diff_state.host_win, diff_state.host_prev_buf, diff_state.saved_sizes = nil, nil, nil
	end

	local function show_proposed_diff(target_file, temp_file)
		-- Remember where focus started (typically the Claude terminal) so we can
		-- return to it — the diff is a passive preview, the approval prompt lives
		-- in the terminal.
		local origin_win = vim.api.nvim_get_current_win()

		-- Clear any previous proposed-diff before opening a new one.
		close_proposed_diff()

		-- Snapshot every window's size (keyed by stable window id) so we can
		-- restore the exact layout on teardown.
		diff_state.saved_sizes = {}
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			diff_state.saved_sizes[w] = { vim.api.nvim_win_get_width(w), vim.api.nvim_win_get_height(w) }
		end

		without_flicker(function()
			-- Find a normal file window to host the "before" side. Skip the origin
			-- window and any terminal/special buffers so we never bury the terminal.
			local host = nil
			for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if w ~= origin_win then
					local bt = vim.bo[vim.api.nvim_win_get_buf(w)].buftype
					if bt == "" or bt == "acwrite" then
						host = w
						break
					end
				end
			end

			if host then
				diff_state.host_win = host
				diff_state.host_prev_buf = vim.api.nvim_win_get_buf(host)
				vim.api.nvim_set_current_win(host)
				vim.cmd("edit " .. vim.fn.fnameescape(target_file))
				diff_state.created_before = false
			else
				-- No spare editor window: open one on the far left, leaving the
				-- terminal (and everything else) untouched.
				vim.cmd("topleft vsplit " .. vim.fn.fnameescape(target_file))
				host = vim.api.nvim_get_current_win()
				diff_state.created_before = true
			end
			diff_state.before_win = host
			vim.cmd("diffthis") -- BEFORE (current on-disk content) on the left

			-- Proposed content ("after") in a split to the right.
			vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(temp_file))
			local after_win = vim.api.nvim_get_current_win()
			local abuf = vim.api.nvim_win_get_buf(after_win)
			vim.bo[abuf].buftype = "nofile"
			vim.bo[abuf].bufhidden = "wipe"
			vim.bo[abuf].swapfile = false
			vim.bo[abuf].modifiable = false
			vim.cmd("diffthis") -- AFTER on the right
			diff_state.after_win = after_win

			-- Keep every pre-existing window (terminal, other editors) at its
			-- original size so opening the diff doesn't shrink them; before/after
			-- absorb the host window's space instead. Skipped in the terminal-only
			-- case (created_before) -- there is no spare room, so the windows must
			-- share and forcing the terminal to full width would collapse the diff.
			if not diff_state.created_before then
				restore_sizes(diff_state.before_win)
			end

			-- Hand focus back to the Claude terminal so you can approve/deny in place.
			if vim.api.nvim_win_is_valid(origin_win) then
				vim.api.nvim_set_current_win(origin_win)
				if vim.bo[vim.api.nvim_win_get_buf(origin_win)].buftype == "terminal" then
					vim.cmd("startinsert")
				end
			end
		end)
	end

	-- Expose as globals for remote-expr invocation from the hook. Defer the UI
	-- work with vim.schedule so it runs outside the RPC fast-context (needed for
	-- window switching + startinsert to behave).
	_G.ClaudeShowProposedDiff = function(target_file, temp_file)
		vim.schedule(function()
			pcall(show_proposed_diff, target_file, temp_file)
		end)
	end

	_G.ClaudeCloseProposedDiff = function()
		vim.schedule(function()
			pcall(close_proposed_diff)
		end)
	end

	-- Define user commands
	vim.api.nvim_create_user_command("ClaudeShowProposedDiff", function(opts)
		local args = vim.split(opts.args, " ")
		if #args < 2 then
			return
		end
		_G.ClaudeShowProposedDiff(args[1], args[2])
	end, { nargs = "*" })

	vim.api.nvim_create_user_command("ClaudeCloseProposedDiff", function()
		_G.ClaudeCloseProposedDiff()
	end, {})

	vim.api.nvim_create_user_command("ClaudeChat", function()
		open_terminal()
	end, {})

	vim.api.nvim_create_user_command("ClaudeContinue", function()
		open_terminal({ "--continue" })
	end, {})

	vim.api.nvim_create_user_command("ClaudeToggleLayout", function()
		toggle_layout()
	end, {})

	vim.api.nvim_create_user_command("ClaudeDiff", function()
		toggle_diff()
	end, {})

	vim.api.nvim_create_user_command("ClaudeAsk", function()
		vim.ui.input({ prompt = "Ask Claude: " }, function(input)
			if not input or input == "" then
				return
			end
			open_terminal({ input })
		end)
	end, {})

	vim.api.nvim_create_user_command("ClaudeExplain", function(opts)
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
		open_terminal({ prompt })
	end, { range = true })

	vim.api.nvim_create_user_command("ClaudeFix", function()
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
		open_terminal({ prompt })
	end, {})

	vim.api.nvim_create_user_command("ClaudeRefactor", function(opts)
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
				'Please refactor the following code block in %s (file: `%s`, lines %d-%d) according to this instruction: "%s"\n\nCode:\n\n```%s\n%s\n```',
				filetype,
				relative_path,
				start_line,
				end_line,
				input,
				filetype,
				code
			)
			open_terminal({ prompt })
		end)
	end, { range = true })

	-- Register keymaps
	local wk_status, wk = pcall(require, "which-key")
	if wk_status then
		wk.add({
			{ "<leader>a", group = "[A]I (Claude)", mode = { "n", "x" } },
			{ "<leader>ac", "<cmd>ClaudeChat<cr>", desc = "Chat" },
			{ "<leader>aC", "<cmd>ClaudeContinue<cr>", desc = "Continue Last Chat" },
			{ "<leader>aa", "<cmd>ClaudeAsk<cr>", desc = "Ask Prompt" },
			{ "<leader>ae", "<cmd>ClaudeExplain<cr>", desc = "Explain Code", mode = { "n", "x" } },
			{ "<leader>af", "<cmd>ClaudeFix<cr>", desc = "Fix Code / Diagnostics" },
			{ "<leader>ar", "<cmd>ClaudeRefactor<cr>", desc = "Refactor Code", mode = { "n", "x" } },
			{ "<leader>al", "<cmd>ClaudeToggleLayout<cr>", desc = "Toggle Layout (Float/Split)" },
			{ "<leader>ad", "<cmd>ClaudeDiff<cr>", desc = "Toggle Live Diff (git)" },
		})
	else
		local map = function(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "Claude: " .. desc })
		end
		map("n", "<leader>ac", "<cmd>ClaudeChat<cr>", "Chat")
		map("n", "<leader>aC", "<cmd>ClaudeContinue<cr>", "Continue Last Chat")
		map("n", "<leader>aa", "<cmd>ClaudeAsk<cr>", "Ask Prompt")
		map({ "n", "x" }, "<leader>ae", "<cmd>ClaudeExplain<cr>", "Explain Code")
		map("n", "<leader>af", "<cmd>ClaudeFix<cr>", "Fix Code / Diagnostics")
		map({ "n", "x" }, "<leader>ar", "<cmd>ClaudeRefactor<cr>", "Refactor Code")
		map("n", "<leader>al", "<cmd>ClaudeToggleLayout<cr>", "Toggle Layout (Float/Split)")
		map("n", "<leader>ad", "<cmd>ClaudeDiff<cr>", "Toggle Live Diff (git)")
	end
end

return M
