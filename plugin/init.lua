local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

-- Add vendored session modules to the search path
local _sep = package.config:sub(1, 1)
for _, plugin in ipairs(wezterm.plugin.list()) do
  if plugin.url:find("workspace%-manager") then
    package.path = plugin.plugin_dir .. _sep .. "plugin" .. _sep .. "?.lua;" .. package.path
    break
  end
end

local M = {}

-- Configuration
M.zoxide_path = "zoxide"
M.wezterm_path = nil -- Optional: auto-detected from wezterm.executable_dir (only needed if auto-detection fails)
M.show_current_workspace_in_switcher = false -- Show current workspace in the switcher list
M.show_current_workspace_hint = true -- Show current workspace name in the switcher description
M.start_in_fuzzy_mode = true -- Start switcher in fuzzy search mode (false = use positional shortcuts)
M.notifications_enabled = false -- Enable toast notifications (requires code-signed wezterm on macOS)
M.workspace_count_format = "compact" -- nil (disabled), "compact" (2w 3t 5p), or "full" (2 wins, 3 tabs, 5 panes)
M.use_basename_for_workspace_names = false -- Use basename only (default: false for backward compatibility)
M.workspace_switcher_sort = "recency" -- "recency" (most recently used first, default) or "alphabetical" (sorted alphabetically)
M.switcher_legend_enabled = true -- Show keybinding legend in right status bar while switcher is open.
                                  -- Set to false if you have your own update-right-status handler, then emit
                                  -- "workspace_manager.switcher.update_right_status" from it manually.
M.switcher_legend = nil -- Override the right status bar content shown while the switcher is open.
                        -- Accepts a list of FormatItems (same syntax as wezterm.format).
                        -- Default: muted-colored "  ^D=del  ^N=new  ^P=path  ^R=rename  Esc=cancel"
M.colors = nil -- Override theme colors. Values accept a color string (AnsiColor name or "#hex") or
               -- a list of FormatItems (e.g. { { Attribute = { Intensity = "Half" } } }):
               --   highlight: current workspace emphasis and prompt accents (default: "Lime")
               --   muted: legend text and secondary separators (default: "#888888")
               --   prompt_heading: prompt heading style: "Bold", "Half", "Normal", or nil (default: "Bold")
               --   switcher_icon: icon glyph style in switcher labels (default: nil = terminal default; current falls back to highlight)
               --   switcher_name: workspace name style in switcher labels (default: nil; current falls back to highlight)
               --   switcher_counts: count suffix style, e.g. "(2w 3t)" (default: nil; current falls back to highlight)
               --   switcher_current: "(current)" marker style (default: nil = falls back to highlight)

-- Session persistence (session integration)
M.session_enabled = false -- Enable automatic workspace state save/restore
M.session_periodic_save_interval = 600 -- Seconds between periodic saves (nil to disable)
M.session_periodic_save_all = false -- Periodic save: true=all in-memory workspaces, false=active workspace only
M.session_max_scrollback_lines = 3500 -- Max scrollback lines to capture per pane
M.session_exclude_workspaces = { "default" } -- Workspace names to never save/restore
M.session_state_dir = nil -- Override state directory (default: ~/.local/share/wezterm/workspace_state/)
M.session_on_pane_restore = nil -- Custom per-pane restore callback (default: default_on_pane_restore)
M.session_restore_on_startup = false -- Restore most recently used workspace on gui-startup

-- ============================================================================
-- Theme / Color Helpers
-- ============================================================================

local DEFAULT_COLORS = {
  highlight = "Lime",
  muted = "#888888",
  prompt_heading = "Bold",
}

local function get_color(key)
  if M.colors and M.colors[key] ~= nil then
    return M.colors[key]
  end
  return DEFAULT_COLORS[key]
end

-- Converts a color string (AnsiColor name or "#hex") to a Foreground FormatItem.
local function fg(color_string)
  if color_string:sub(1, 1) == "#" then
    return { Foreground = { Color = color_string } }
  else
    return { Foreground = { AnsiColor = color_string } }
  end
end

-- Builds a FormatItem list for prompt headings using the configured intensity.
local function build_heading(text)
  local items = {}
  local intensity = get_color("prompt_heading")
  if intensity and intensity ~= "Normal" then
    table.insert(items, { Attribute = { Intensity = intensity } })
  end
  table.insert(items, { Text = text })
  return items
end

-- Resolves a switcher segment color. For current entries, falls back to highlight if the key is nil.
local function get_switcher_color(key, is_current)
  local color = get_color(key)
  if color then return color end
  if is_current then return get_color("highlight") end
  return nil
end

-- Appends a styled text segment to a FormatItems list. Skips empty strings.
-- style can be nil (no styling), a color string (treated as foreground), or
-- a list of FormatItems (e.g. { { Attribute = { Intensity = "Half" } } }).
local function append_segment(items, text, style)
  if text == "" then return end
  table.insert(items, "ResetAttributes")
  if type(style) == "string" then
    table.insert(items, fg(style))
  elseif type(style) == "table" then
    for _, item in ipairs(style) do
      table.insert(items, item)
    end
  end
  table.insert(items, { Text = text })
end

-- Builds a fully formatted switcher label with independently styled segments.
local function build_switcher_label(icon, name, counts, is_current)
  local items = {}
  append_segment(items, icon, get_switcher_color("switcher_icon", is_current))
  append_segment(items, name, get_switcher_color("switcher_name", is_current))
  append_segment(items, counts, get_switcher_color("switcher_counts", is_current))
  if is_current then
    append_segment(items, " (current)", get_switcher_color("switcher_current", is_current))
  end
  table.insert(items, "ResetAttributes")
  return wezterm.format(items)
end

-- ============================================================================
-- Switcher State
-- ============================================================================

-- Tracks which action the key table intercepted so the InputSelector callback
-- can dispatch to kill/rename/new instead of the default switch.
local switcher_state = {
  pending_action = nil, -- "delete" | "rename" | "new" | nil (nil = default switch)
}

-- Creates a key table entry that sets pending_action, pops the key table, and
-- sends a synthetic Enter to close the InputSelector and fire its callback.
local function switcher_keymap(key, mods, action)
  return {
    key = key,
    mods = mods,
    action = wezterm.action_callback(function(window, pane)
      switcher_state.pending_action = action
      window:perform_action(act.PopKeyTable, pane)
      window:perform_action(act.SendKey({ key = "Enter" }), pane)
    end),
  }
end

-- Creates a key table entry that clears pending_action, pops the key table,
-- and forwards the key to InputSelector (used for Escape to cancel).
local function switcher_keymap_cancel(key, mods)
  return {
    key = key,
    mods = mods or "NONE",
    action = wezterm.action_callback(function(window, pane)
      switcher_state.pending_action = nil
      window:perform_action(act.PopKeyTable, pane)
      window:perform_action(act.SendKey({ key = key }), pane)
    end),
  }
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function notify(window, title, message, timeout)
  if not M.notifications_enabled then return end
  pcall(function()
    window:toast_notification(title, message, nil, timeout or 2000)
  end)
end

local function get_wezterm_path()
  if M.wezterm_path then
    return M.wezterm_path  -- User override
  end

  local exe_dir = wezterm.executable_dir
  if not exe_dir then
    return nil
  end

  local is_windows = wezterm.target_triple:find("windows") ~= nil
  local exe_name = is_windows and "wezterm.exe" or "wezterm"

  return exe_dir .. "/" .. exe_name
end

-- ============================================================================
-- Path Normalization
-- ============================================================================

local function normalize_workspace_name(name)
  if not name then return name end
  -- If starts with ~, expand to full path for cwd operations
  local expanded = string.gsub(name, "^~", wezterm.home_dir)
  -- For display/storage, always use ~ prefix for home paths
  local normalized = string.gsub(expanded, "^" .. wezterm.home_dir, "~")
  return normalized, expanded
end

local function get_workspace_name_and_path(raw_path)
  local normalized, expanded = normalize_workspace_name(raw_path)

  if not M.use_basename_for_workspace_names then
    return normalized, expanded
  end

  -- Extract basename
  local basename = string.match(normalized, "([^/]+)$")

  -- Fallback if extraction fails
  if not basename or basename == "" then
    return normalized, expanded
  end

  -- Check for duplicate basenames
  for _, ws in ipairs(mux.get_workspace_names()) do
    local ws_normalized = normalize_workspace_name(ws)
    if ws == basename and ws_normalized ~= normalized then
      -- Conflict: fall back to full path
      return normalized, expanded
    end
  end

  return basename, expanded
end

-- ============================================================================
-- Persistence Layer
-- ============================================================================

local WORKSPACE_HISTORY_DIR = wezterm.home_dir .. "/.local/share/wezterm"
local WORKSPACE_HISTORY_FILE = WORKSPACE_HISTORY_DIR .. "/workspace_history.json"

local function ensure_history_dir()
  os.execute('mkdir -p "' .. WORKSPACE_HISTORY_DIR .. '"')
end

local function load_workspace_history()
  local file = io.open(WORKSPACE_HISTORY_FILE, "r")
  if file then
    local content = file:read("*all")
    file:close()
    local success, data = pcall(wezterm.json_parse, content)
    if success then return data end
  end
  return {}
end

local function save_workspace_history(history)
  ensure_history_dir()
  local file = io.open(WORKSPACE_HISTORY_FILE, "w")
  if file then
    file:write(wezterm.json_encode(history))
    file:close()
  end
end

local function update_workspace_access_time(workspace_name)
  local normalized = normalize_workspace_name(workspace_name)
  wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times or {}
  wezterm.GLOBAL.workspace_access_times[normalized] = os.time()
  save_workspace_history(wezterm.GLOBAL.workspace_access_times)
end

-- Initialize on first load
wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times or load_workspace_history()

-- ============================================================================
-- Session Persistence (Resurrect Integration)
-- ============================================================================

-- Lazy-loaded session modules (only required when session_enabled = true)
local _workspace_state_mod = nil
local _tab_state_mod = nil
local _file_io_mod = nil

local function get_session_modules()
  if not _workspace_state_mod then
    _workspace_state_mod = require("session.workspace_state")
    _tab_state_mod = require("session.tab_state")
    _file_io_mod = require("session.file_io")
  end
  return _workspace_state_mod, _tab_state_mod, _file_io_mod
end

local function get_state_dir()
  if M.session_state_dir then
    return M.session_state_dir
  end
  return WORKSPACE_HISTORY_DIR .. "/workspace_state"
end

local function ensure_state_dir()
  os.execute('mkdir -p "' .. get_state_dir() .. '"')
end

local function is_excluded_workspace(name)
  local normalized = normalize_workspace_name(name)
  for _, excluded in ipairs(M.session_exclude_workspaces) do
    if normalized == excluded or name == excluded then
      return true
    end
  end
  return false
end

local _is_windows = wezterm.target_triple:find("windows") ~= nil
local _path_sep = _is_windows and "\\" or "/"

-- Sanitize a workspace name for use as a filename (replace path separators with +)
local function workspace_name_to_filename(name)
  return name:gsub(_path_sep, "+")
end

-- Reverse filename encoding back to workspace name
local function filename_to_workspace_name(filename)
  -- Remove .json extension, then replace + back to path separator
  local name = filename:gsub("%.json$", "")
  return name:gsub("%+", _path_sep)
end

local function get_state_file_path(workspace_name)
  return get_state_dir() .. "/" .. workspace_name_to_filename(workspace_name) .. ".json"
end

local function get_most_recent_saved_workspace()
  local history = load_workspace_history()
  local entries = {}
  for name, time in pairs(history) do
    if not is_excluded_workspace(name) then
      table.insert(entries, { name = name, time = time })
    end
  end
  table.sort(entries, function(a, b) return a.time > b.time end)
  for _, entry in ipairs(entries) do
    local f = io.open(get_state_file_path(entry.name), "r")
    if f then
      f:close()
      return entry.name
    end
  end
  return nil
end

local function save_workspace_state(workspace_name, gui_win)
  if is_excluded_workspace(workspace_name) then return end

  local workspace_state_mod, _, file_io = get_session_modules()
  ensure_state_dir()

  local ok, err = pcall(function()
    local state = workspace_state_mod.get_workspace_state_for(workspace_name)
    if state and state.window_states and #state.window_states > 0 then
      -- Inject full window pixel dimensions when called from a GUI event context.
      -- mux_window:gui_window() only works for the *active* workspace, so we accept the
      -- GuiWindow directly from callers that already have it.
      if gui_win then
        local dims = gui_win:get_dimensions()
        if state.window_states[1] then
          state.window_states[1].window_pixel_width = dims.pixel_width
          state.window_states[1].window_pixel_height = dims.pixel_height
        end
      end
      local path = get_state_file_path(workspace_name)
      file_io.write_state(path, state, "workspace")
      wezterm.log_info("workspace_manager: saved state for workspace '" .. workspace_name .. "'")
    end
  end)
  if not ok then
    wezterm.log_error("workspace_manager: failed to save state for '" .. workspace_name .. "': " .. tostring(err))
  end
end

local function load_workspace_state(workspace_name)
  local _, _, file_io = get_session_modules()
  local path = get_state_file_path(workspace_name)
  local ok, state = pcall(function()
    return file_io.load_json(path)
  end)
  if ok and state and state.window_states then
    wezterm.log_info("workspace_manager: loaded state for workspace '" .. workspace_name .. "'")
    return state
  end
  return nil
end

local function delete_workspace_state(workspace_name)
  local path = get_state_file_path(workspace_name)
  local ok = os.remove(path)
  if ok then
    wezterm.log_info("workspace_manager: deleted state file for workspace '" .. workspace_name .. "'")
  end
end

local function restore_workspace_state(workspace_name, mux_window, restore_opts)
  local workspace_state_mod, tab_state_mod, _ = get_session_modules()
  local state = load_workspace_state(workspace_name)
  if state then
    local on_pane_restore = M.session_on_pane_restore or tab_state_mod.default_on_pane_restore
    local opts = {
      window = mux_window,
      relative = true,
      close_open_panes = true,
      on_pane_restore = on_pane_restore,
      resize_window = false,
    }
    if restore_opts then
      for k, v in pairs(restore_opts) do
        opts[k] = v
      end
    end
    local ok, err = pcall(function()
      workspace_state_mod.restore_workspace(state, opts)
    end)
    if not ok then
      wezterm.log_error("workspace_manager: failed to restore state for '" .. workspace_name .. "': " .. tostring(err))
    end
  end
end

local function wait_for_stable_window(window, interval_s, stable_samples, max_checks, on_ready)
  local checks = 0
  local stable_count = 0
  local last_w, last_h

  local function sample()
    checks = checks + 1
    local ok, dims_or_err = pcall(function()
      local gui_win = window:gui_window()
      if not gui_win then
        error("missing gui_window")
      end
      return gui_win:get_dimensions()
    end)

    if not ok then
      wezterm.log_warn("workspace_manager: window stability wait aborted: " .. tostring(dims_or_err))
      on_ready(false)
      return
    end

    local dims = dims_or_err
    local w = dims.pixel_width
    local h = dims.pixel_height

    if last_w == w and last_h == h then
      stable_count = stable_count + 1
    else
      stable_count = 0
    end
    last_w = w
    last_h = h

    if stable_count >= stable_samples then
      on_ready(true)
      return
    end

    if checks >= max_checks then
      wezterm.log_warn("workspace_manager: window did not stabilize before timeout; continuing restore")
      on_ready(false)
      return
    end

    wezterm.time.call_after(interval_s, sample)
  end

  sample()
end

-- Returns workspace names that have saved state on disk (excluding excluded and live workspaces)
local function get_saved_workspace_names()
  local state_dir = get_state_dir()
  local names = {}

  -- Use wezterm.read_dir if available, otherwise fall back to ls/dir
  local ok, entries = pcall(wezterm.read_dir, state_dir)
  if not ok or not entries then
    return names
  end

  -- Build set of live workspace names (normalized)
  local live_set = {}
  for _, ws in ipairs(mux.get_workspace_names()) do
    live_set[normalize_workspace_name(ws)] = true
    live_set[ws] = true
  end

  for _, entry in ipairs(entries) do
    -- entry is a full path; extract just the filename
    local filename = entry:match("([^/\\]+)$")
    if filename and filename:match("%.json$") then
      local ws_name = filename_to_workspace_name(filename)
      local normalized = normalize_workspace_name(ws_name)
      if not live_set[ws_name] and not live_set[normalized] and not is_excluded_workspace(ws_name) then
        table.insert(names, ws_name)
      end
    end
  end

  return names
end

-- ============================================================================
-- Data Gathering
-- ============================================================================

local function get_workspace_choices()
  local choices = {}
  local access_times = wezterm.GLOBAL.workspace_access_times or {}

  -- Live (in-memory) workspaces
  for _, ws in ipairs(mux.get_workspace_names()) do
    local normalized = normalize_workspace_name(ws)
    table.insert(choices, {
      id = ws,
      label = normalized,
      normalized = normalized,
      is_workspace = true,
      is_saved = false,
      access_time = access_times[normalized] or 0
    })
  end

  -- Saved (on-disk only) workspaces, when session is enabled
  if M.session_enabled then
    for _, ws_name in ipairs(get_saved_workspace_names()) do
      local normalized = normalize_workspace_name(ws_name)
      table.insert(choices, {
        id = ws_name,
        label = normalized,
        normalized = normalized,
        is_workspace = true,
        is_saved = true,
        access_time = access_times[normalized] or access_times[ws_name] or 0
      })
    end
  end

  table.sort(choices, function(a, b)
    return a.access_time > b.access_time
  end)

  return choices
end

local function get_workspace_cycle_order()
  local choices = {}

  for _, ws in ipairs(mux.get_workspace_names()) do
    local normalized = normalize_workspace_name(ws)
    table.insert(choices, {
      id = ws,
      label = normalized,
      normalized = normalized,
      is_saved = false,
    })
  end

  -- Sort alphabetically (case-insensitive) for predictable cycling
  table.sort(choices, function(a, b)
    return a.normalized:lower() < b.normalized:lower()
  end)

  return choices
end

-- Returns workspace choices sorted alphabetically, including saved workspaces when session is enabled
local function get_workspace_choices_alphabetical()
  local choices = get_workspace_choices()
  table.sort(choices, function(a, b)
    return a.normalized:lower() < b.normalized:lower()
  end)
  return choices
end

local function get_zoxide_choices(workspace_normalized_set)
  local choices = {}
  local success, stdout, stderr = wezterm.run_child_process({
    M.zoxide_path, "query", "-l"
  })

  if success then
    for _, path in ipairs(wezterm.split_by_newlines(stdout)) do
      if path ~= "" then
        local normalized = normalize_workspace_name(path)
        if not workspace_normalized_set[normalized] then
          table.insert(choices, {
            id = path,
            label = normalized,
            normalized = normalized,
            is_workspace = false
          })
        end
      end
    end
  end

  return choices
end

local function get_workspace_counts()
  local counts = {}

  for _, mux_win in ipairs(mux.all_windows()) do
    local ws = mux_win:get_workspace()
    if not counts[ws] then
      counts[ws] = { windows = 0, tabs = 0, panes = 0 }
    end
    counts[ws].windows = counts[ws].windows + 1
    for _, tab in ipairs(mux_win:tabs()) do
      counts[ws].tabs = counts[ws].tabs + 1
      counts[ws].panes = counts[ws].panes + #tab:panes()
    end
  end

  return counts
end

local function format_counts(counts, format)
  if not counts or not format then return "" end

  local parts = {}

  if format == "compact" then
    if counts.windows > 1 then
      table.insert(parts, counts.windows .. "w")
    end
    if counts.tabs > 1 or counts.windows > 1 then
      table.insert(parts, counts.tabs .. "t")
    end
    if counts.panes > 1 or counts.tabs > 1 then
      table.insert(parts, counts.panes .. "p")
    end
    if #parts == 0 then return "" end
    return " (" .. table.concat(parts, " ") .. ")"
  elseif format == "full" then
    if counts.windows > 1 then
      table.insert(parts, counts.windows .. " wins")
    end
    if counts.tabs > 1 or counts.windows > 1 then
      table.insert(parts, counts.tabs .. " tabs")
    end
    if counts.panes > 1 or counts.tabs > 1 then
      table.insert(parts, counts.panes .. " panes")
    end
    if #parts == 0 then return "" end
    return " (" .. table.concat(parts, ", ") .. ")"
  end

  return ""
end

---Get the MuxWindow for a given workspace
---@param workspace string
---@return MuxWindow
local function get_current_mux_window(workspace)
  wezterm.log_info("get_current_mux_window called for workspace: " .. tostring(workspace))
  local all_wins = mux.all_windows()
  wezterm.log_info("Total mux windows: " .. tostring(#all_wins))

  for _, mux_win in ipairs(all_wins) do
    local ws = mux_win:get_workspace()
    wezterm.log_info("Checking mux_win workspace: " .. tostring(ws) .. " against " .. tostring(workspace))
    if ws == workspace then
      wezterm.log_info("Found matching MuxWindow!")
      wezterm.log_info("MuxWindow type: " .. tostring(type(mux_win)))
      wezterm.log_info("Has gui_window method: " .. tostring(type(mux_win.gui_window)))
      return mux_win
    end
  end
  wezterm.log_error("Could not find a workspace with the name: " .. tostring(workspace))
  error("Could not find a workspace with the name: " .. workspace)
end

-- ============================================================================
-- Action Handlers
-- ============================================================================

local function do_close_workspace(workspace_name, window, pane)
  wezterm.log_info("workspace_manager: do_close_workspace called for: " .. tostring(workspace_name))

  local wezterm_path = get_wezterm_path()
  if not wezterm_path then
    wezterm.log_warn("workspace_manager: wezterm_path not found")
    notify(window, "Workspace Manager", "Failed to detect wezterm path. Please set wezterm_path manually.", 4000)
    return
  end

  local current_workspace = window:active_workspace()
  wezterm.log_info("workspace_manager: current_workspace=" .. tostring(current_workspace) .. " target=" .. tostring(workspace_name))

  if workspace_name == current_workspace then
    wezterm.log_warn("workspace_manager: blocked — cannot close active workspace")
    notify(window, "Workspace", "Cannot close active workspace")
    return
  end

  -- Get all panes via CLI (most reliable method)
  local success, stdout, stderr = wezterm.run_child_process({
    wezterm_path, "cli", "list", "--format=json"
  })

  if not success then
    wezterm.log_warn("workspace_manager: cli list failed: " .. tostring(stderr))
    notify(window, "Workspace", "Failed to list panes: " .. tostring(stderr), 4000)
    return
  end

  local panes = wezterm.json_parse(stdout)
  local panes_to_kill = {}

  -- Diagnostic: dump all workspace names seen in cli list output
  local ws_names_seen = {}
  for _, p in ipairs(panes) do
    ws_names_seen[p.workspace or "nil"] = true
  end
  local ws_list = {}
  for k in pairs(ws_names_seen) do table.insert(ws_list, '"' .. k .. '"') end
  wezterm.log_info("workspace_manager: workspaces in cli list: " .. table.concat(ws_list, ", "))
  wezterm.log_info("workspace_manager: looking for workspace: \"" .. workspace_name .. "\"")

  for _, p in ipairs(panes) do
    if p.workspace == workspace_name then
      table.insert(panes_to_kill, p.pane_id)
    end
  end

  wezterm.log_info("workspace_manager: found " .. #panes_to_kill .. " panes to kill in workspace: " .. workspace_name)

  if #panes_to_kill == 0 then
    wezterm.log_warn("workspace_manager: no panes found for workspace: " .. workspace_name)
    notify(window, "Workspace", "No panes found in workspace")
    return
  end

  if #panes_to_kill > 1 then
    notify(window, "Workspace", "Closing " .. #panes_to_kill .. " panes in: " .. workspace_name)
  end

  -- Kill each pane
  for _, pane_id in ipairs(panes_to_kill) do
    local kill_ok, _, kill_err = wezterm.run_child_process({
      wezterm_path, "cli", "kill-pane", "--pane-id=" .. tostring(pane_id)
    })
    if kill_ok then
      wezterm.log_info("workspace_manager: killed pane " .. tostring(pane_id))
    else
      wezterm.log_warn("workspace_manager: failed to kill pane " .. tostring(pane_id) .. ": " .. tostring(kill_err))
    end
  end

  -- Remove from history
  local normalized = normalize_workspace_name(workspace_name)
  if wezterm.GLOBAL.workspace_access_times then
    wezterm.GLOBAL.workspace_access_times[normalized] = nil
    save_workspace_history(wezterm.GLOBAL.workspace_access_times)
  end

  -- Delete saved state so it doesn't reappear after restart
  if M.session_enabled then
    delete_workspace_state(workspace_name)
    wezterm.log_info("workspace_manager: deleted saved state for: " .. workspace_name)
  end
end

local function do_rename_workspace(old_name, new_name, window, pane)
  if not new_name or new_name == "" or new_name == old_name then
    return
  end

  local new_normalized = normalize_workspace_name(new_name)

  -- Check if target name already exists (merge scenario)
  local name_exists = false
  for _, ws in ipairs(mux.get_workspace_names()) do
    local ws_normalized = normalize_workspace_name(ws)
    if ws_normalized == new_normalized then
      name_exists = true
      break
    end
  end

  if name_exists then
    notify(window, "Workspace Rename", 'Merging "' .. old_name .. '" into existing "' .. new_normalized .. '"', 3000)
    -- For merge: move windows to existing workspace
    for _, mux_win in ipairs(mux.all_windows()) do
      if mux_win:get_workspace() == old_name then
        mux_win:set_workspace(new_normalized)
      end
    end
  else
    -- Use built-in rename function
    mux.rename_workspace(old_name, new_normalized)
  end

  -- Update history
  local old_normalized = normalize_workspace_name(old_name)
  if wezterm.GLOBAL.workspace_access_times then
    local old_time = wezterm.GLOBAL.workspace_access_times[old_normalized]
    wezterm.GLOBAL.workspace_access_times[old_normalized] = nil
    wezterm.GLOBAL.workspace_access_times[new_normalized] = old_time or os.time()
    save_workspace_history(wezterm.GLOBAL.workspace_access_times)
  end

  -- Rename state file if it exists
  if M.session_enabled then
    local old_path = get_state_file_path(old_name)
    local new_path = get_state_file_path(new_normalized)
    os.rename(old_path, new_path)
  end

  notify(window, "Workspace Rename", 'Renamed "' .. old_name .. '" to "' .. new_normalized .. '"')
end

-- ============================================================================
-- Exported Actions
-- ============================================================================

function M.workspace_switcher()
  return wezterm.action_callback(function(window, pane)
    local workspace_choices
    if M.workspace_switcher_sort == "alphabetical" then
      workspace_choices = get_workspace_choices_alphabetical()
    else
      workspace_choices = get_workspace_choices()
    end

    local workspace_normalized_set = {}
    for _, choice in ipairs(workspace_choices) do
      workspace_normalized_set[choice.normalized] = true
    end

    local zoxide_choices = get_zoxide_choices(workspace_normalized_set)

    -- Get workspace counts if format is enabled
    local workspace_counts = nil
    if M.workspace_count_format then
      workspace_counts = get_workspace_counts()
    end

    local current_workspace = window:active_workspace()
    local current_normalized = normalize_workspace_name(current_workspace)

    -- Track which ids are live workspaces, saved (disk-only) workspaces
    local existing_workspace_ids = {}
    local saved_workspace_ids = {}
    for _, choice in ipairs(workspace_choices) do
      if choice.is_saved then
        saved_workspace_ids[choice.id] = true
      else
        existing_workspace_ids[choice.id] = true
      end
    end

    local all_choices = {}
    for _, choice in ipairs(workspace_choices) do
      local is_current = (choice.id == current_workspace)

      -- Skip current workspace if configured to hide it
      if is_current and not M.show_current_workspace_in_switcher then
        -- skip
      else
        local count_suffix = ""
        if workspace_counts and workspace_counts[choice.id] then
          count_suffix = format_counts(workspace_counts[choice.id], M.workspace_count_format)
        end

        local label = build_switcher_label("󱂬  ", choice.label, count_suffix, is_current)
        table.insert(all_choices, { id = choice.id, label = label })
      end
    end
    for _, choice in ipairs(zoxide_choices) do
      table.insert(all_choices, {
        id = choice.id,
        label = build_switcher_label("  ", choice.label, "", false),
      })
    end

    if #all_choices == 0 then
      notify(window, "Workspace", "No other workspaces available")
      return
    end

    -- Build description with optional current workspace hint
    local description
    local fuzzy_description
    if M.show_current_workspace_hint then
      description = wezterm.format({
        fg(get_color("highlight")),
        { Text = "Current: " .. current_normalized },
        fg(get_color("muted")),
        { Text = " | ^D=del ^N=new ^P=path ^R=rename | Esc=cancel" },
      })
      fuzzy_description = wezterm.format({
        fg(get_color("highlight")),
        { Text = "Current: " .. current_normalized },
        fg(get_color("muted")),
        { Text = " | Switch to: " },
      })
    else
      description = "Enter=switch | ^D=del | ^N=new | ^P=path | ^R=rename | Esc=cancel"
      fuzzy_description = "Switch to: "
    end

    -- Activate the key table so Ctrl+D/N/P/R are intercepted while the overlay is open
    switcher_state.pending_action = nil
    window:perform_action(
      act.ActivateKeyTable { name = "workspace_switcher_actions", one_shot = false },
      pane
    )

    window:perform_action(
      act.InputSelector {
        title = "Workspace Switcher",
        description = description,
        fuzzy = M.start_in_fuzzy_mode,
        fuzzy_description = fuzzy_description,
        choices = all_choices,
        action = wezterm.action_callback(function(win, p, id, label)
          local pending = switcher_state.pending_action
          switcher_state.pending_action = nil

          -- Cancelled (Escape or click-outside) — do nothing
          if not id and not label then
            return
          end

          if pending == "delete" then
            wezterm.log_info("workspace_manager: switcher delete action, id=" .. tostring(id))
            if id == win:active_workspace() then
              wezterm.log_warn("workspace_manager: switcher blocked delete of active workspace")
              notify(win, "Workspace", "Cannot delete active workspace")
            elseif saved_workspace_ids[id] then
              -- Saved-only workspace: no live panes to kill, just remove state + history
              wezterm.log_info("workspace_manager: deleting saved-only workspace: " .. id)
              local normalized = normalize_workspace_name(id)
              if wezterm.GLOBAL.workspace_access_times then
                wezterm.GLOBAL.workspace_access_times[normalized] = nil
                save_workspace_history(wezterm.GLOBAL.workspace_access_times)
              end
              if M.session_enabled then
                delete_workspace_state(id)
              end
            else
              do_close_workspace(id, win, p)
            end
            -- Re-open switcher after delete so user can continue
            wezterm.time.call_after(0.1, function()
              win:perform_action(M.workspace_switcher(), p)
            end)

          elseif pending == "rename" then
            win:perform_action(
              act.PromptInputLine {
                description = wezterm.format {
                  fg(get_color("highlight")),
                  { Text = "Renaming: " .. normalize_workspace_name(id) },
                  fg(get_color("muted")),
                  { Text = " | Enter new name:" },
                },
                action = wezterm.action_callback(function(inner_win, inner_p, line)
                  if line and line ~= "" then
                    do_rename_workspace(id, line, inner_win, inner_p)
                    -- Re-open switcher after rename so user can continue
                    wezterm.time.call_after(0.1, function()
                      inner_win:perform_action(M.workspace_switcher(), inner_p)
                    end)
                  end
                end),
              },
              p
            )

          elseif pending == "new" then
            win:perform_action(
              act.PromptInputLine {
                description = wezterm.format(build_heading("Enter name for new workspace:")),
                action = wezterm.action_callback(function(inner_win, inner_p, line)
                  if line and line ~= "" then
                    local old_workspace = inner_win:active_workspace()
                    if M.session_enabled and old_workspace and not is_excluded_workspace(old_workspace) then
                      save_workspace_state(old_workspace, inner_win)
                    end
                    if old_workspace then
                      local old_mux_window = get_current_mux_window(old_workspace)
                      wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, inner_p, old_workspace, line)
                    end
                    inner_win:perform_action(act.SwitchToWorkspace { name = line }, inner_p)
                    update_workspace_access_time(line)
                    local new_mux_window = get_current_mux_window(line)
                    if M.session_enabled then
                      restore_workspace_state(line, new_mux_window)
                    end
                    wezterm.emit("workspace_manager.workspace_switcher.created", new_mux_window, inner_p, line)
                  end
                end),
              },
              p
            )

          elseif pending == "new_at_path" then
            win:perform_action(
              act.PromptInputLine {
                description = wezterm.format(build_heading("Enter path for new workspace:")),
                action = wezterm.action_callback(function(inner_win, inner_p, line)
                  if line and line ~= "" then
                    local workspace_name, expanded_path = get_workspace_name_and_path(line)
                    local old_workspace = inner_win:active_workspace()
                    if M.session_enabled and old_workspace and not is_excluded_workspace(old_workspace) then
                      save_workspace_state(old_workspace, inner_win)
                    end
                    if old_workspace then
                      local old_mux_window = get_current_mux_window(old_workspace)
                      wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, inner_p, old_workspace, workspace_name)
                    end
                    inner_win:perform_action(
                      act.SwitchToWorkspace { name = workspace_name, spawn = { cwd = expanded_path } },
                      inner_p
                    )
                    update_workspace_access_time(workspace_name)
                    wezterm.run_child_process({ M.zoxide_path, "add", "--", line })
                    local new_mux_window = get_current_mux_window(workspace_name)
                    if M.session_enabled then
                      restore_workspace_state(workspace_name, new_mux_window)
                    end
                    wezterm.emit("workspace_manager.workspace_switcher.created", new_mux_window, inner_p, workspace_name, expanded_path)
                  end
                end),
              },
              p
            )

          else
            -- Default: switch to selected workspace
            local is_existing_workspace = existing_workspace_ids[id]
            local is_saved_workspace = saved_workspace_ids[id]

            if is_existing_workspace then
              local old_workspace = win:active_workspace()
              if M.session_enabled and old_workspace and not is_excluded_workspace(old_workspace) then
                save_workspace_state(old_workspace, win)
              end
              if old_workspace then
                local old_mux_window = get_current_mux_window(old_workspace)
                wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, p, old_workspace, id)
              end
              win:perform_action(act.SwitchToWorkspace({ name = id }), p)
              update_workspace_access_time(id)
              local new_mux_window = get_current_mux_window(id)
              wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, p, id)

            elseif is_saved_workspace then
              local old_workspace = win:active_workspace()
              if M.session_enabled and old_workspace and not is_excluded_workspace(old_workspace) then
                save_workspace_state(old_workspace, win)
              end
              if old_workspace then
                local old_mux_window = get_current_mux_window(old_workspace)
                wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, p, old_workspace, id)
              end
              win:perform_action(act.SwitchToWorkspace({ name = id }), p)
              update_workspace_access_time(id)
              local new_mux_window = get_current_mux_window(id)
              restore_workspace_state(id, new_mux_window)
              wezterm.emit("workspace_manager.workspace_switcher.created", new_mux_window, p, id)

            else
              -- Zoxide path: create new workspace at path
              local workspace_name, expanded_path = get_workspace_name_and_path(id)
              local old_workspace = win:active_workspace()
              if M.session_enabled and old_workspace and not is_excluded_workspace(old_workspace) then
                save_workspace_state(old_workspace, win)
              end
              if old_workspace then
                local old_mux_window = get_current_mux_window(old_workspace)
                wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, p, old_workspace, workspace_name)
              end
              win:perform_action(
                act.SwitchToWorkspace({ name = workspace_name, spawn = { cwd = expanded_path } }),
                p
              )
              update_workspace_access_time(workspace_name)
              wezterm.run_child_process({ M.zoxide_path, "add", "--", id })
              local new_mux_window = get_current_mux_window(workspace_name)
              if M.session_enabled then
                restore_workspace_state(workspace_name, new_mux_window)
              end
              wezterm.emit("workspace_manager.workspace_switcher.created", new_mux_window, p, workspace_name, expanded_path)
            end
          end
        end)
      },
      pane
    )
  end)
end

function M.switch_to_previous_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local previous_workspace = wezterm.GLOBAL.previous_workspace

    if current_workspace == previous_workspace or previous_workspace == nil then
      return
    end

    -- Save current workspace state before switching
    if M.session_enabled and not is_excluded_workspace(current_workspace) then
      save_workspace_state(current_workspace, window)
    end

    wezterm.GLOBAL.previous_workspace = current_workspace

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = get_current_mux_window(current_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, pane, current_workspace, previous_workspace)

    window:perform_action(act.SwitchToWorkspace({ name = previous_workspace }), pane)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = get_current_mux_window(previous_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, pane, previous_workspace)
  end)
end

function M.next_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local choices = get_workspace_cycle_order()

    if #choices <= 1 then
      notify(window, "Workspace", "No other workspaces available")
      return
    end

    -- Find current workspace in the sorted list
    local current_index = nil
    for i, choice in ipairs(choices) do
      if choice.id == current_workspace then
        current_index = i
        break
      end
    end

    -- If not found, start from first (shouldn't happen but safe)
    if not current_index then
      current_index = 0
    end

    -- Calculate next index with wrapping
    local next_index = (current_index % #choices) + 1
    local next_workspace = choices[next_index].id

    local old_workspace = window:active_workspace()

    -- Save old workspace state before switching
    if M.session_enabled and not is_excluded_workspace(old_workspace) then
      save_workspace_state(old_workspace, window)
    end

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = get_current_mux_window(old_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, pane, old_workspace, next_workspace)

    window:perform_action(act.SwitchToWorkspace({ name = next_workspace }), pane)
    update_workspace_access_time(next_workspace)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = get_current_mux_window(next_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, pane, next_workspace)
  end)
end

function M.previous_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local choices = get_workspace_cycle_order()

    if #choices <= 1 then
      notify(window, "Workspace", "No other workspaces available")
      return
    end

    -- Find current workspace in the sorted list
    local current_index = nil
    for i, choice in ipairs(choices) do
      if choice.id == current_workspace then
        current_index = i
        break
      end
    end

    -- If not found, start from last
    if not current_index then
      current_index = 1
    end

    -- Calculate previous index with wrapping
    local prev_index = current_index - 1
    if prev_index < 1 then
      prev_index = #choices
    end
    local prev_workspace = choices[prev_index].id

    local old_workspace = window:active_workspace()

    -- Save old workspace state before switching
    if M.session_enabled and not is_excluded_workspace(old_workspace) then
      save_workspace_state(old_workspace, window)
    end

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = get_current_mux_window(old_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, pane, old_workspace, prev_workspace)

    window:perform_action(act.SwitchToWorkspace({ name = prev_workspace }), pane)
    update_workspace_access_time(prev_workspace)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = get_current_mux_window(prev_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, pane, prev_workspace)
  end)
end

-- ============================================================================
-- Config Application
-- ============================================================================

function M.apply_to_config(config)
  -- Emit "workspace_manager.switcher.update_right_status" whenever the switcher key table
  -- is active. The default handler below renders the legend into the right status bar.
  --
  -- If you have your own update-right-status handler, set switcher_legend_enabled = false
  -- to disable the plugin's handler, then emit this event yourself:
  --
  --   workspace_manager.switcher_legend_enabled = false
  --
  --   wezterm.on("update-right-status", function(window, pane)
  --     if window:active_key_table() == "workspace_switcher_actions" then
  --       wezterm.emit("workspace_manager.switcher.update_right_status", window, pane)
  --       return
  --     end
  --     -- your normal right status logic here
  --   end)
  wezterm.on("workspace_manager.switcher.update_right_status", function(window, _pane)
    if M.switcher_legend then
      window:set_right_status(wezterm.format(M.switcher_legend))
    else
      window:set_right_status(wezterm.format({
        fg(get_color("muted")),
        { Text = "  ^D=del  ^N=new  ^P=path  ^R=rename  Esc=cancel" },
      }))
    end
  end)

  if M.switcher_legend_enabled then
    wezterm.on("update-right-status", function(window, pane)
      if window:active_key_table() == "workspace_switcher_actions" then
        wezterm.emit("workspace_manager.switcher.update_right_status", window, pane)
      else
        window:set_right_status("")
      end
    end)
  end

  -- Track previous workspace on focus change
  wezterm.on("window-focus-changed", function(window, pane)
    if window and window.active_workspace then
      local current = window:active_workspace()
      if wezterm.GLOBAL.last_focused_workspace and wezterm.GLOBAL.last_focused_workspace ~= current then
        wezterm.GLOBAL.previous_workspace = wezterm.GLOBAL.last_focused_workspace
      end
      wezterm.GLOBAL.last_focused_workspace = current
    end
  end)

  -- Session persistence setup
  if M.session_enabled then
    -- Apply max scrollback lines config
    local pane_tree_mod = require("session.pane_tree")
    pane_tree_mod.max_nlines = M.session_max_scrollback_lines

    -- Periodic save timer
    if M.session_periodic_save_interval then
      local function periodic_save()
        wezterm.time.call_after(M.session_periodic_save_interval, function()
          if M.session_periodic_save_all then
            for _, ws_name in ipairs(mux.get_workspace_names()) do
              if not is_excluded_workspace(ws_name) then
                save_workspace_state(ws_name)
              end
            end
          else
            local active = mux.get_active_workspace()
            if active and not is_excluded_workspace(active) then
              save_workspace_state(active)
            end
          end
          periodic_save()
        end)
      end
      periodic_save()
    end

    -- Restore most recently used workspace on startup
    if M.session_restore_on_startup then
      wezterm.on("gui-startup", function(_cmd)
        local workspace_name = get_most_recent_saved_workspace()
        if not workspace_name then return end
        local state = load_workspace_state(workspace_name)
        if not state then return end
        local _, expanded = normalize_workspace_name(workspace_name)

        local ws = state.window_states and state.window_states[1]
        local has_saved_pixels = ws and ws.window_pixel_width and ws.window_pixel_height
        -- Spawn window first; startup restore will wait for geometry to settle
        -- and then restore panes to avoid post-restore split reflow.
        local spawn_args = { workspace = workspace_name, cwd = expanded }
        if not has_saved_pixels and ws and ws.size then
          spawn_args.width = ws.size.cols
          spawn_args.height = ws.size.rows
        end
        local _, _, window = mux.spawn_window(spawn_args)

        local function do_restore()
          restore_workspace_state(workspace_name, window, {
            relative = true,
            close_open_panes = true,
            resize_window = false,
          })
          update_workspace_access_time(workspace_name)
          wezterm.GLOBAL.last_focused_workspace = workspace_name
        end

        wait_for_stable_window(window, 0.10, 2, 15, function()
          if has_saved_pixels then
            local ok, err = pcall(function()
              local gui_win = window:gui_window()
              if gui_win then
                gui_win:set_inner_size(ws.window_pixel_width, ws.window_pixel_height)
              else
                error("missing gui_window while applying startup pixel size")
              end
            end)
            if not ok then
              wezterm.log_warn("workspace_manager: failed to apply startup pixel size: " .. tostring(err))
              do_restore()
              return
            end
            wait_for_stable_window(window, 0.10, 2, 8, function()
              do_restore()
            end)
            return
          end
          do_restore()
        end)
      end)
    end
  end

  -- Key table for in-switcher actions (Ctrl+D=del, Ctrl+N=new, Ctrl+P=path, Ctrl+R=rename)
  config.key_tables = config.key_tables or {}
  config.key_tables.workspace_switcher_actions = {
    switcher_keymap_cancel("Enter"),  -- pop key table, then forward Enter to select
    switcher_keymap("d", "CTRL", "delete"),
    switcher_keymap("n", "CTRL", "new"),
    switcher_keymap("p", "CTRL", "new_at_path"),
    switcher_keymap("r", "CTRL", "rename"),
    switcher_keymap_cancel("Escape"),
  }

  -- Default keybindings (users can override by setting their own keys)
  local keys = config.keys or {}

  table.insert(keys, {
    key = "s",
    mods = "LEADER",
    action = M.workspace_switcher(),
  })

  table.insert(keys, {
    key = "S",
    mods = "LEADER",
    action = M.switch_to_previous_workspace(),
  })

  table.insert(keys, {
    key = "]",
    mods = "CTRL",
    action = M.next_workspace(),
  })

  table.insert(keys, {
    key = "[",
    mods = "CTRL",
    action = M.previous_workspace(),
  })

  config.keys = keys
end

return M
