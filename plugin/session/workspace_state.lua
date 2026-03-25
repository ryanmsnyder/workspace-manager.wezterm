local wezterm = require("wezterm") --[[@as Wezterm]]
local window_state_mod = require("session.window_state")

local pub = {}

---restore workspace state
---@param workspace_state workspace_state
---@param opts? restore_opts
function pub.restore_workspace(workspace_state, opts)
	if workspace_state == nil then
		return
	end

	if opts == nil then
		opts = {}
	end

	local restored_windows = {}

	for i, window_state in ipairs(workspace_state.window_states) do
		if i == 1 and opts.window then
			if opts.resize_window == true or opts.resize_window == nil then
				-- Prefer window_pixel_width/height (full inner area, compatible with set_inner_size)
				-- over size.pixel_width/height (cell grid only, causes window to shrink).
				local pw = window_state.window_pixel_width or window_state.size.pixel_width
				local ph = window_state.window_pixel_height or window_state.size.pixel_height
				opts.window:gui_window():set_inner_size(pw, ph)
				wezterm.sleep_ms(200)
			end
			if not opts.close_open_tabs then
				opts.tab = opts.window:active_tab()
				if not opts.close_open_panes then
					opts.pane = opts.window:active_pane()
				end
			end
		else
			local spawn_window_args = {
				width = window_state.size.cols,
				height = window_state.size.rows,
				cwd = window_state.tabs[1].pane_tree.cwd,
			}
			if opts.spawn_in_workspace then
				spawn_window_args.workspace = workspace_state.workspace
			end
			opts.tab, opts.pane, opts.window = wezterm.mux.spawn_window(spawn_window_args)
		end

		window_state_mod.restore_window(opts.window, window_state, opts)
		restored_windows[i] = opts.window
	end

	-- Focus the window that was focused at save time.
	for i, window_state in ipairs(workspace_state.window_states) do
		if window_state.is_focused and restored_windows[i] then
			local focus_ok, gui_win = pcall(function()
				return restored_windows[i]:gui_window()
			end)
			if focus_ok and gui_win then
				gui_win:focus()
			end
			break
		end
	end
end

---Returns the state of the currently active workspace
---@return workspace_state
function pub.get_workspace_state()
	return pub.get_workspace_state_for(wezterm.mux.get_active_workspace())
end

---Returns the state of a specific workspace by name
---@param workspace_name string
---@return workspace_state
function pub.get_workspace_state_for(workspace_name)
	local workspace_state = {
		workspace = workspace_name,
		window_states = {},
	}

	-- Determine which GUI window is currently focused so we can stamp is_focused.
	local focused_id = nil
	local ok, gui_wins = pcall(wezterm.gui.gui_windows)
	if ok and gui_wins then
		for _, gw in ipairs(gui_wins) do
			if gw:is_focused() then
				focused_id = gw:window_id()
				break
			end
		end
	end

	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		if mux_win:get_workspace() == workspace_name then
			local ws = window_state_mod.get_window_state(mux_win)
			ws.window_id = mux_win:window_id()
			ws.is_focused = (mux_win:window_id() == focused_id)
			table.insert(workspace_state.window_states, ws)
		end
	end
	return workspace_state
end

return pub
