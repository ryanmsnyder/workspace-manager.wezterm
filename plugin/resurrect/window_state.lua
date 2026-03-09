local wezterm = require("wezterm") --[[@as Wezterm]]
local tab_state_mod = require("resurrect.tab_state")
local pub = {}

---Returns the state of the window
---@param window MuxWindow
---@return window_state
function pub.get_window_state(window)
	local window_state = {
		title = window:get_title(),
		tabs = {},
	}

	local tabs = window:tabs_with_info()

	for i, tab in ipairs(tabs) do
		local tab_state = tab_state_mod.get_tab_state(tab.tab)
		tab_state.is_active = tab.is_active
		window_state.tabs[i] = tab_state
	end

	local size_tab = tabs[1].tab
	for _, tab in ipairs(tabs) do
		if tab.is_active then
			size_tab = tab.tab
			break
		end
	end
	window_state.size = size_tab:get_size()

	return window_state
end

---Force closes all other tabs in the window but one
---@param window MuxWindow
---@param tab_to_keep MuxTab
local function close_all_other_tabs(window, tab_to_keep)
	for _, tab in ipairs(window:tabs()) do
		if tab:tab_id() ~= tab_to_keep:tab_id() then
			tab:activate()
			window
				:gui_window()
				:perform_action(wezterm.action.CloseCurrentTab({ confirm = false }), window:active_pane())
		end
	end
end

---restore window state
---@param window MuxWindow
---@param window_state window_state
---@param opts? restore_opts
function pub.restore_window(window, window_state, opts)
	if opts == nil then
		opts = {}
	end

	if window_state.title then
		window:set_title(window_state.title)
	end

	local active_tab
	for i, tab_state in ipairs(window_state.tabs) do
		local tab
		if i == 1 and opts.tab then
			tab = opts.tab
		else
			local spawn_tab_args = { cwd = tab_state.pane_tree.cwd }
			if tab_state.pane_tree.domain then
				spawn_tab_args.domain = { DomainName = tab_state.pane_tree.domain }
			end
			tab, opts.pane, _ = window:spawn_tab(spawn_tab_args)
		end

		if i == 1 and opts.close_open_tabs then
			close_all_other_tabs(window, tab)
		end

		tab_state_mod.restore_tab(tab, tab_state, opts)
		if tab_state.is_active then
			active_tab = tab
		end

		if tab_state.is_zoomed then
			tab:set_zoomed(true)
		end
	end

	if active_tab then
		active_tab:activate()
	end
end

return pub
