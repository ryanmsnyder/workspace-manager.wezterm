local wezterm = require("wezterm")
local mux = wezterm.mux

local M_ref -- reference to plugin config table (set via setup)

local mod = {}

-- Platform constants
mod.is_windows = wezterm.target_triple:find("windows") ~= nil
mod.path_sep = mod.is_windows and "\\" or "/"

function mod.setup(plugin)
  M_ref = plugin
end

function mod.notify(window, title, message, timeout)
  if not M_ref.notifications_enabled then return end
  pcall(function()
    window:toast_notification(title, message, nil, timeout or 2000)
  end)
end

function mod.get_wezterm_path()
  if M_ref.wezterm_path then
    return M_ref.wezterm_path  -- User override
  end

  local exe_dir = wezterm.executable_dir
  if not exe_dir then
    return nil
  end

  local exe_name = mod.is_windows and "wezterm.exe" or "wezterm"
  return exe_dir .. "/" .. exe_name
end

-- ============================================================================
-- Path Normalization
-- ============================================================================

function mod.normalize_workspace_name(name)
  if not name then return name end
  -- If starts with ~, expand to full path for cwd operations
  local expanded = string.gsub(name, "^~", wezterm.home_dir)
  -- For display/storage, always use ~ prefix for home paths
  local normalized = string.gsub(expanded, "^" .. wezterm.home_dir, "~")
  return normalized, expanded
end

function mod.get_workspace_name_and_path(raw_path)
  local normalized, expanded = mod.normalize_workspace_name(raw_path)

  if not M_ref.use_basename_for_workspace_names then
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
    local ws_normalized = mod.normalize_workspace_name(ws)
    if ws == basename and ws_normalized ~= normalized then
      -- Conflict: fall back to full path
      return normalized, expanded
    end
  end

  return basename, expanded
end

-- ============================================================================
-- Platform Filesystem Helpers
-- ============================================================================

function mod.directory_exists(path)
  if mod.is_windows then
    local success = wezterm.run_child_process({"cmd", "/c", "if exist \"" .. path .. "\\\" (exit 0) else (exit 1)"})
    return success
  else
    local success = wezterm.run_child_process({"test", "-d", path})
    return success
  end
end

function mod.create_directory(path)
  if mod.is_windows then
    return wezterm.run_child_process({"cmd", "/c", "mkdir", path})
  else
    return wezterm.run_child_process({"mkdir", "-p", path})
  end
end

return mod
