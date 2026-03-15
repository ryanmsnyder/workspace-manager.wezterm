local wezterm = require("wezterm")
local mux = wezterm.mux

local M_ref   -- reference to plugin config table (set via setup)
local helpers -- set via setup
local state   -- set via setup

local mod = {}

function mod.setup(plugin, deps)
  M_ref   = plugin
  helpers = deps.helpers
  state   = deps.state
end

function mod.get_workspace_choices()
  local choices = {}
  local access_times = wezterm.GLOBAL.workspace_access_times or {}

  -- Live (in-memory) workspaces
  for _, ws in ipairs(mux.get_workspace_names()) do
    local normalized = helpers.normalize_workspace_name(ws)
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
  if M_ref.session_enabled then
    for _, ws_name in ipairs(state.get_saved_workspace_names()) do
      local normalized = helpers.normalize_workspace_name(ws_name)
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

function mod.get_workspace_cycle_order()
  local choices = {}

  for _, ws in ipairs(mux.get_workspace_names()) do
    local normalized = helpers.normalize_workspace_name(ws)
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
function mod.get_workspace_choices_alphabetical()
  local choices = mod.get_workspace_choices()
  table.sort(choices, function(a, b)
    return a.normalized:lower() < b.normalized:lower()
  end)
  return choices
end

function mod.get_zoxide_choices(workspace_normalized_set)
  local choices = {}
  local success, stdout, _ = wezterm.run_child_process({
    M_ref.zoxide_path, "query", "-l"
  })

  if success then
    for _, path in ipairs(wezterm.split_by_newlines(stdout)) do
      if path ~= "" then
        local normalized = helpers.normalize_workspace_name(path)
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

function mod.get_custom_choices(workspace_normalized_set)
  if M_ref.get_choices == false then
    return {}, false, {}
  end

  if type(M_ref.get_choices) == "function" then
    local raw = M_ref.get_choices() or {}
    local choices = {}
    local label_overrides = {} -- name -> custom label (applied to live workspace entries too)
    for _, entry in ipairs(raw) do
      local name, path, label
      if type(entry) == "string" then
        -- Treat as a path: derive name from path for display
        path = entry
        name = helpers.normalize_workspace_name(entry)
      elseif type(entry) == "table" then
        name = entry.name
        path = entry.path
        label = entry.label
      end
      if name then
        if label then
          label_overrides[name] = label
        end
        local normalized = helpers.normalize_workspace_name(name)
        if not workspace_normalized_set[normalized] then
          table.insert(choices, {
            id = name, -- always keyed by name so it doesn't collide with existing workspace ids
            name = name,
            path = path, -- stored separately; nil for name-only entries
            label = label or normalized,
            normalized = normalized,
            is_workspace = false,
            has_path = path ~= nil,
          })
        end
      end
    end
    return choices, false, label_overrides
  end

  -- Default: built-in zoxide
  return mod.get_zoxide_choices(workspace_normalized_set), true, {}
end

function mod.get_workspace_counts()
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

function mod.format_counts(counts, format)
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
function mod.get_current_mux_window(workspace)
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

return mod
