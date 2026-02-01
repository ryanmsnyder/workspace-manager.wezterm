local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local M = {}

-- Configuration
M.zoxide_path = "zoxide"

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
-- Data Gathering
-- ============================================================================

local function get_workspace_choices()
  local choices = {}
  local access_times = wezterm.GLOBAL.workspace_access_times or {}

  for _, ws in ipairs(mux.get_workspace_names()) do
    local normalized = normalize_workspace_name(ws)
    table.insert(choices, {
      id = ws,
      label = normalized,
      normalized = normalized,
      is_workspace = true,
      access_time = access_times[normalized] or 0
    })
  end

  table.sort(choices, function(a, b)
    return a.access_time > b.access_time
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

-- ============================================================================
-- Action Handlers
-- ============================================================================

local function do_close_workspace(workspace_name, window, pane)
  local windows_in_workspace = {}
  local current_workspace = window:active_workspace()

  if workspace_name == current_workspace then
    window:toast_notification("Workspace", "Cannot close active workspace", nil, 2000)
    return
  end

  for _, mux_win in ipairs(mux.all_windows()) do
    if mux_win:get_workspace() == workspace_name then
      table.insert(windows_in_workspace, mux_win)
    end
  end

  if #windows_in_workspace > 1 then
    window:toast_notification(
      "Workspace",
      "Closing " .. #windows_in_workspace .. " windows in workspace: " .. workspace_name,
      nil, 2000
    )
  end

  for _, mux_win in ipairs(windows_in_workspace) do
    local gui_win = mux_win:gui_window()
    if gui_win then
      while #mux_win:tabs() > 0 do
        local tab = mux_win:tabs()[1]
        local tab_pane = tab:active_pane()
        if tab_pane then
          tab_pane:close()
        end
        wezterm.sleep_ms(10)
      end
    end
  end

  local normalized = normalize_workspace_name(workspace_name)
  if wezterm.GLOBAL.workspace_access_times then
    wezterm.GLOBAL.workspace_access_times[normalized] = nil
    save_workspace_history(wezterm.GLOBAL.workspace_access_times)
  end
end

local function do_rename_workspace(old_name, new_name, window)
  if not new_name or new_name == "" or new_name == old_name then
    return
  end

  local new_normalized = normalize_workspace_name(new_name)

  local name_exists = false
  for _, ws in ipairs(mux.get_workspace_names()) do
    local ws_normalized = normalize_workspace_name(ws)
    if ws_normalized == new_normalized then
      name_exists = true
      break
    end
  end

  if name_exists then
    window:toast_notification(
      "Workspace Rename",
      'Merging "' .. old_name .. '" into existing "' .. new_normalized .. '"',
      nil, 3000
    )
  end

  for _, mux_win in ipairs(mux.all_windows()) do
    if mux_win:get_workspace() == old_name then
      mux_win:set_workspace(new_normalized)
    end
  end

  local old_normalized = normalize_workspace_name(old_name)
  if wezterm.GLOBAL.workspace_access_times then
    local old_time = wezterm.GLOBAL.workspace_access_times[old_normalized]
    wezterm.GLOBAL.workspace_access_times[old_normalized] = nil
    wezterm.GLOBAL.workspace_access_times[new_normalized] = old_time or os.time()
    save_workspace_history(wezterm.GLOBAL.workspace_access_times)
  end

  window:toast_notification(
    "Workspace Rename",
    'Renamed "' .. old_name .. '" to "' .. new_normalized .. '"',
    nil, 2000
  )
end

-- ============================================================================
-- Exported Actions
-- ============================================================================

function M.switch_workspace()
  return wezterm.action_callback(function(window, pane)
    local workspace_choices = get_workspace_choices()

    local workspace_normalized_set = {}
    for _, choice in ipairs(workspace_choices) do
      workspace_normalized_set[choice.normalized] = true
    end

    local zoxide_choices = get_zoxide_choices(workspace_normalized_set)

    local all_choices = {}
    for _, choice in ipairs(workspace_choices) do
      table.insert(all_choices, {
        id = choice.id,
        label = "󱂬  " .. choice.label
      })
    end
    for _, choice in ipairs(zoxide_choices) do
      table.insert(all_choices, {
        id = choice.id,
        label = "  " .. choice.label
      })
    end

    local existing_workspace_ids = {}
    for _, choice in ipairs(workspace_choices) do
      existing_workspace_ids[choice.id] = true
    end

    window:perform_action(
      act.InputSelector {
        title = "Switch Workspace",
        description = "Enter=switch | /=filter | Esc=cancel",
        fuzzy = true,
        fuzzy_description = "Fuzzy search: ",
        choices = all_choices,
        action = wezterm.action_callback(function(win, p, id, label)
          if id then
            local is_existing_workspace = existing_workspace_ids[id]

            if is_existing_workspace then
              win:perform_action(act.SwitchToWorkspace({ name = id }), p)
              update_workspace_access_time(id)
            else
              local normalized, expanded = normalize_workspace_name(id)
              win:perform_action(
                act.SwitchToWorkspace({
                  name = normalized,
                  spawn = { cwd = expanded }
                }),
                p
              )
              update_workspace_access_time(normalized)

              wezterm.run_child_process({
                M.zoxide_path, "add", "--", id
              })
            end
          end
        end)
      },
      pane
    )
  end)
end

function M.new_workspace()
  return act.PromptInputLine {
    description = "Enter path for new workspace:",
    action = wezterm.action_callback(function(window, pane, line)
      if line and line ~= "" then
        local normalized, expanded = normalize_workspace_name(line)
        window:perform_action(
          act.SwitchToWorkspace {
            name = normalized,
            spawn = { cwd = expanded }
          },
          pane
        )
        update_workspace_access_time(normalized)
      end
    end)
  }
end

function M.close_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local workspaces = mux.get_workspace_names()
    local choices = {}

    for _, ws in ipairs(workspaces) do
      if ws ~= current_workspace then
        local normalized = normalize_workspace_name(ws)
        table.insert(choices, { id = ws, label = normalized })
      end
    end

    if #choices == 0 then
      window:toast_notification("Workspace", "No other workspaces to close", nil, 2000)
      return
    end

    window:perform_action(
      act.InputSelector {
        title = "Close Workspace",
        description = "Select workspace to close",
        fuzzy = true,
        choices = choices,
        action = wezterm.action_callback(function(win, p, id, label)
          if id then
            do_close_workspace(id, win, p)
          end
        end)
      },
      pane
    )
  end)
end

function M.rename_workspace()
  return act.PromptInputLine {
    description = "Enter new name for current workspace:",
    action = wezterm.action_callback(function(window, pane, line)
      if line and line ~= "" then
        local old_name = window:active_workspace()
        do_rename_workspace(old_name, line, window)
      end
    end)
  }
end

function M.switch_to_previous_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local previous_workspace = wezterm.GLOBAL.previous_workspace

    if current_workspace == previous_workspace or previous_workspace == nil then
      return
    end

    wezterm.GLOBAL.previous_workspace = current_workspace
    window:perform_action(act.SwitchToWorkspace({ name = previous_workspace }), pane)
  end)
end

-- ============================================================================
-- Config Application
-- ============================================================================

function M.apply_to_config(config)
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

  -- Default keybindings (users can override by setting their own keys)
  local keys = config.keys or {}

  table.insert(keys, {
    key = "s",
    mods = "LEADER",
    action = M.switch_workspace(),
  })

  table.insert(keys, {
    key = "n",
    mods = "LEADER",
    action = M.new_workspace(),
  })

  table.insert(keys, {
    key = "x",
    mods = "LEADER",
    action = M.close_workspace(),
  })

  table.insert(keys, {
    key = "r",
    mods = "LEADER",
    action = M.rename_workspace(),
  })

  table.insert(keys, {
    key = "S",
    mods = "LEADER",
    action = M.switch_to_previous_workspace(),
  })

  config.keys = keys
end

return M
