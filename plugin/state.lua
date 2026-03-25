local wezterm = require("wezterm")
local mux = wezterm.mux

local M_ref   -- reference to plugin config table (set via setup)
local helpers -- set via setup
local history -- set via setup

local mod = {}

-- Lazy-loaded session modules (only required when session_enabled = true)
local _workspace_state_mod = nil
local _tab_state_mod = nil
local _file_io_mod = nil

function mod.setup(plugin, deps)
  M_ref   = plugin
  helpers = deps.helpers
  history = deps.history
end

local function get_session_modules()
  if not _workspace_state_mod then
    _workspace_state_mod = require("session.workspace_state")
    _tab_state_mod = require("session.tab_state")
    _file_io_mod = require("session.file_io")
  end
  return _workspace_state_mod, _tab_state_mod, _file_io_mod
end

function mod.get_state_dir()
  if M_ref.session_state_dir then
    return M_ref.session_state_dir
  end
  return history.HISTORY_DIR .. "/workspace_state"
end

local function ensure_state_dir()
  os.execute('mkdir -p "' .. mod.get_state_dir() .. '"')
end

function mod.is_excluded_workspace(name)
  local normalized = helpers.normalize_workspace_name(name)
  for _, excluded in ipairs(M_ref.session_exclude_workspaces) do
    if normalized == excluded or name == excluded then
      return true
    end
  end
  return false
end

-- Sanitize a workspace name for use as a filename (replace path separators with +)
local function workspace_name_to_filename(name)
  return name:gsub(helpers.path_sep, "+")
end

-- Reverse filename encoding back to workspace name
local function filename_to_workspace_name(filename)
  -- Remove .json extension, then replace + back to path separator
  local name = filename:gsub("%.json$", "")
  return name:gsub("%+", helpers.path_sep)
end

local function get_state_file_path(workspace_name)
  return mod.get_state_dir() .. "/" .. workspace_name_to_filename(workspace_name) .. ".json"
end

function mod.get_most_recent_saved_workspace()
  local hist = history.load()
  local entries = {}
  for name, time in pairs(hist) do
    if not mod.is_excluded_workspace(name) then
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

function mod.save_workspace_state(workspace_name, gui_win)
  if mod.is_excluded_workspace(workspace_name) then return end

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
        local target_id = gui_win:mux_window():window_id()
        local matched = false
        for _, ws in ipairs(state.window_states) do
          if ws.window_id == target_id then
            ws.window_pixel_width = dims.pixel_width
            ws.window_pixel_height = dims.pixel_height
            matched = true
            break
          end
        end
        -- Fallback: inject into first window if no id match (shouldn't happen).
        if not matched and state.window_states[1] then
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

function mod.load_workspace_state(workspace_name)
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

function mod.delete_workspace_state(workspace_name)
  local path = get_state_file_path(workspace_name)
  local ok = os.remove(path)
  if ok then
    wezterm.log_info("workspace_manager: deleted state file for workspace '" .. workspace_name .. "'")
  end
end

function mod.rename_workspace_state(old_name, new_name)
  local old_path = get_state_file_path(old_name)
  local new_path = get_state_file_path(new_name)
  os.rename(old_path, new_path)
end

function mod.restore_workspace_state(workspace_name, mux_window, restore_opts)
  local workspace_state_mod, tab_state_mod, _ = get_session_modules()
  local state = mod.load_workspace_state(workspace_name)
  if state then
    local on_pane_restore = M_ref.session_on_pane_restore or tab_state_mod.default_on_pane_restore
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

function mod.wait_for_stable_window(window, interval_s, stable_samples, max_checks, on_ready)
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
function mod.get_saved_workspace_names()
  local state_dir = mod.get_state_dir()
  local names = {}

  local ok, entries = pcall(wezterm.read_dir, state_dir)
  if not ok or not entries then
    return names
  end

  -- Build set of live workspace names (normalized)
  local live_set = {}
  for _, ws in ipairs(mux.get_workspace_names()) do
    live_set[helpers.normalize_workspace_name(ws)] = true
    live_set[ws] = true
  end

  for _, entry in ipairs(entries) do
    -- entry is a full path; extract just the filename
    local filename = entry:match("([^/\\]+)$")
    if filename and filename:match("%.json$") then
      local ws_name = filename_to_workspace_name(filename)
      local normalized = helpers.normalize_workspace_name(ws_name)
      if not live_set[ws_name] and not live_set[normalized] and not mod.is_excluded_workspace(ws_name) then
        table.insert(names, ws_name)
      end
    end
  end

  return names
end

return mod
