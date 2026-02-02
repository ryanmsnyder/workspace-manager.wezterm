local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local M = {}

-- Configuration
M.zoxide_path = "zoxide"
M.wezterm_path = nil -- Required: user must set this (e.g., "/Applications/WezTerm.app/Contents/MacOS/wezterm")
M.show_current_in_switcher = true -- Show current workspace in the switcher list
M.show_current_workspace_hint = false -- Show current workspace name in the switcher description
M.start_in_fuzzy_mode = true -- Start switcher in fuzzy search mode (false = use positional shortcuts)

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
  wezterm.log_info("do_close_workspace called, wezterm_path = " .. tostring(M.wezterm_path))

  if not M.wezterm_path then
    window:toast_notification(
      "Workspace Manager",
      "wezterm_path not configured. See README for setup.",
      nil, 4000
    )
    return
  end

  local current_workspace = window:active_workspace()

  if workspace_name == current_workspace then
    window:toast_notification("Workspace", "Cannot close active workspace", nil, 2000)
    return
  end

  -- Get all panes via CLI (most reliable method)
  local success, stdout, stderr = wezterm.run_child_process({
    M.wezterm_path, "cli", "list", "--format=json"
  })

  wezterm.log_info("CLI list result: success=" .. tostring(success) .. ", stdout=" .. tostring(stdout) .. ", stderr=" .. tostring(stderr))

  if not success then
    window:toast_notification("Workspace", "Failed to list panes: " .. tostring(stderr), nil, 4000)
    return
  end

  local panes = wezterm.json_parse(stdout)
  local panes_to_kill = {}

  for _, p in ipairs(panes) do
    if p.workspace == workspace_name then
      table.insert(panes_to_kill, p.pane_id)
    end
  end

  if #panes_to_kill == 0 then
    window:toast_notification("Workspace", "No panes found in workspace", nil, 2000)
    return
  end

  if #panes_to_kill > 1 then
    window:toast_notification(
      "Workspace",
      "Closing " .. #panes_to_kill .. " panes in: " .. workspace_name,
      nil, 2000
    )
  end

  -- Kill each pane
  for _, pane_id in ipairs(panes_to_kill) do
    wezterm.run_child_process({
      M.wezterm_path, "cli", "kill-pane", "--pane-id=" .. tostring(pane_id)
    })
  end

  -- Remove from history
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

    local current_workspace = window:active_workspace()
    local current_normalized = normalize_workspace_name(current_workspace)
    local all_choices = {}
    for _, choice in ipairs(workspace_choices) do
      local is_current = (choice.id == current_workspace)

      -- Skip current workspace if configured to hide it
      if is_current and not M.show_current_in_switcher then
        -- skip
      else
        local label
        if is_current then
          label = wezterm.format({
            { Foreground = { AnsiColor = "Lime" } },
            { Text = "󱂬  " .. choice.label .. " (current)" },
          })
        else
          label = "󱂬  " .. choice.label
        end
        table.insert(all_choices, { id = choice.id, label = label })
      end
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

    -- Build description with optional current workspace hint
    local description
    local fuzzy_description
    if M.show_current_workspace_hint then
      description = wezterm.format({
        { Foreground = { AnsiColor = "Lime" } },
        { Text = "Current: " .. current_normalized },
        { Foreground = { Color = "#888888" } },
        { Text = " | Enter=switch | /=filter | Esc=cancel" },
      })
      fuzzy_description = wezterm.format({
        { Foreground = { AnsiColor = "Lime" } },
        { Text = "Current: " .. current_normalized },
        { Foreground = { Color = "#888888" } },
        { Text = " | Switch to: " },
      })
    else
      description = "Enter=switch | /=filter | Esc=cancel"
      fuzzy_description = "Switch to: "
    end

    window:perform_action(
      act.InputSelector {
        title = "Switch Workspace",
        description = description,
        fuzzy = M.start_in_fuzzy_mode,
        fuzzy_description = fuzzy_description,
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
    description = wezterm.format {
      { Attribute = { Intensity = "Bold" } },
      { Text = "Enter name for new workspace:" },
    },
    action = wezterm.action_callback(function(window, pane, line)
      if line and line ~= "" then
        window:perform_action(
          act.SwitchToWorkspace { name = line },
          pane
        )
        update_workspace_access_time(line)
      end
    end)
  }
end

function M.new_workspace_at_path()
  return act.PromptInputLine {
    description = wezterm.format {
      { Attribute = { Intensity = "Bold" } },
      { Text = "Enter path for new workspace:" },
    },
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
    local current_normalized = normalize_workspace_name(current_workspace)
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

    -- Build description with optional current workspace hint
    local description
    local fuzzy_description
    if M.show_current_workspace_hint then
      description = wezterm.format({
        { Foreground = { AnsiColor = "Lime" } },
        { Text = "Current: " .. current_normalized },
        { Foreground = { Color = "#888888" } },
        { Text = " | Enter=close | /=filter | Esc=cancel" },
      })
      fuzzy_description = wezterm.format({
        { Foreground = { AnsiColor = "Lime" } },
        { Text = "Current: " .. current_normalized },
        { Foreground = { Color = "#888888" } },
        { Text = " | Select workspace to close: " },
      })
    else
      description = "Enter=close | /=filter | Esc=cancel"
      fuzzy_description = "Select workspace to close: "
    end

    window:perform_action(
      act.InputSelector {
        title = "Close Workspace",
        description = description,
        fuzzy = M.start_in_fuzzy_mode,
        fuzzy_description = fuzzy_description,
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
    key = "N",
    mods = "LEADER|SHIFT",
    action = M.new_workspace_at_path(),
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
