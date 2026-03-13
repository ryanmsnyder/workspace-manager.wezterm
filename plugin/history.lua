local wezterm = require("wezterm")

local M_ref   -- reference to plugin config table (set via setup)
local helpers -- set via setup

local mod = {}

mod.HISTORY_DIR  = wezterm.home_dir .. "/.local/share/wezterm"
mod.HISTORY_FILE = mod.HISTORY_DIR .. "/workspace_history.json"

function mod.setup(plugin, deps)
  M_ref   = plugin
  helpers = deps.helpers
end

local function ensure_dir()
  os.execute('mkdir -p "' .. mod.HISTORY_DIR .. '"')
end

function mod.load()
  local file = io.open(mod.HISTORY_FILE, "r")
  if file then
    local content = file:read("*all")
    file:close()
    local success, data = pcall(wezterm.json_parse, content)
    if success then return data end
  end
  return {}
end

function mod.save(history)
  ensure_dir()
  local file = io.open(mod.HISTORY_FILE, "w")
  if file then
    file:write(wezterm.json_encode(history))
    file:close()
  end
end

function mod.update_access_time(workspace_name)
  local normalized = helpers.normalize_workspace_name(workspace_name)
  wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times or {}
  wezterm.GLOBAL.workspace_access_times[normalized] = os.time()
  mod.save(wezterm.GLOBAL.workspace_access_times)
end

-- Initialize on first load
wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times or mod.load()

return mod
