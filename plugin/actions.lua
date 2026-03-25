local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local M_ref   -- reference to plugin config table (set via setup)
local theme   -- set via setup
local helpers -- set via setup
local history -- set via setup
local state   -- set via setup
local data    -- set via setup

local mod = {}

-- ============================================================================
-- Switcher Key Configuration
-- ============================================================================

-- Default in-switcher action key bindings. Single source of truth — key table,
-- description hints, and legend are all generated from this.
local DEFAULT_SWITCHER_KEYS = {
  delete      = { key = "d", mods = "CTRL", hint = "del" },
  new         = { key = "n", mods = "CTRL", hint = "new" },
  new_at_path = { key = "p", mods = "CTRL", hint = "path" },
  rename      = { key = "r", mods = "CTRL", hint = "rename" },
}
-- Explicit order for deterministic hint text (pairs() order is undefined in Lua)
local SWITCHER_KEY_ORDER = { "delete", "new", "new_at_path", "rename" }

-- Returns the resolved key config as an ordered list, merging M_ref.switcher_keys overrides
-- with defaults. Each entry: { key, mods, hint, action_name }. Disabled actions (false) omitted.
local function get_resolved_switcher_keys()
  local result = {}
  local user_keys = M_ref.switcher_keys or {}
  for _, action_name in ipairs(SWITCHER_KEY_ORDER) do
    local override = user_keys[action_name]
    local def = DEFAULT_SWITCHER_KEYS[action_name]
    if override == false then
      -- explicitly disabled
    elseif override == nil then
      table.insert(result, { key = def.key, mods = def.mods, hint = def.hint, action_name = action_name })
    else
      table.insert(result, {
        key = override.key,
        mods = override.mods or "NONE",
        hint = override.hint or def.hint,
        action_name = action_name,
      })
    end
  end
  return result
end

-- Converts a binding to a short display string, e.g. { key="d", mods="CTRL" } => "^D".
local function format_key_hint(binding)
  local mods = binding.mods or "NONE"
  local prefix = ""
  if mods:find("CTRL") then prefix = prefix .. "^" end
  if mods:find("ALT") or mods:find("META") then prefix = prefix .. "M-" end
  if mods:find("SHIFT") then prefix = prefix .. "S-" end
  local key = binding.key
  -- Single-char CTRL-only keys use uppercase convention (^D not ^d)
  if prefix == "^" and #key == 1 then key = key:upper() end
  return prefix .. key
end

-- Builds a hint string from the resolved key config, e.g. "^D=del  ^N=new  ^P=path  ^R=rename".
-- separator: string between entries (default "  "). Returns "" if all actions are disabled.
function mod.build_switcher_hints(separator)
  separator = separator or "  "
  local parts = {}
  for _, binding in ipairs(get_resolved_switcher_keys()) do
    table.insert(parts, format_key_hint(binding) .. "=" .. binding.hint)
  end
  return table.concat(parts, separator)
end

-- Builds the workspace_switcher_actions key table entries from the resolved config.
-- Always includes Enter (select) and Escape (cancel) as non-configurable entries.
function mod.build_switcher_key_table()
  local entries = { mod.switcher_keymap_cancel("Enter") }
  for _, binding in ipairs(get_resolved_switcher_keys()) do
    table.insert(entries, mod.switcher_keymap(binding.key, binding.mods, binding.action_name))
  end
  table.insert(entries, mod.switcher_keymap_cancel("Escape"))
  return entries
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
function mod.switcher_keymap(key, mods, action)
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
function mod.switcher_keymap_cancel(key, mods)
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

function mod.setup(plugin, deps)
  M_ref   = plugin
  theme   = deps.theme
  helpers = deps.helpers
  history = deps.history
  state   = deps.state
  data    = deps.data
end

-- ============================================================================
-- Action Handlers
-- ============================================================================

local function do_close_workspace(workspace_name, window, pane)
  wezterm.log_info("workspace_manager: do_close_workspace called for: " .. tostring(workspace_name))

  local wezterm_path = helpers.get_wezterm_path()
  if not wezterm_path then
    wezterm.log_warn("workspace_manager: wezterm_path not found")
    helpers.notify(window, "Workspace Manager", "Failed to detect wezterm path. Please set wezterm_path manually.", 4000)
    return
  end

  local current_workspace = window:active_workspace()
  wezterm.log_info("workspace_manager: current_workspace=" .. tostring(current_workspace) .. " target=" .. tostring(workspace_name))

  if workspace_name == current_workspace then
    wezterm.log_warn("workspace_manager: blocked — cannot close active workspace")
    helpers.notify(window, "Workspace", "Cannot close active workspace")
    return
  end

  -- Get all panes via CLI (most reliable method)
  local success, stdout, stderr = wezterm.run_child_process({
    wezterm_path, "cli", "list", "--format=json"
  })

  if not success then
    wezterm.log_warn("workspace_manager: cli list failed: " .. tostring(stderr))
    helpers.notify(window, "Workspace", "Failed to list panes: " .. tostring(stderr), 4000)
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
    helpers.notify(window, "Workspace", "No panes found in workspace")
    return
  end

  if #panes_to_kill > 1 then
    helpers.notify(window, "Workspace", "Closing " .. #panes_to_kill .. " panes in: " .. workspace_name)
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
  local normalized = helpers.normalize_workspace_name(workspace_name)
  if wezterm.GLOBAL.workspace_access_times then
    wezterm.GLOBAL.workspace_access_times[normalized] = nil
    history.save(wezterm.GLOBAL.workspace_access_times)
  end

  -- Delete saved state so it doesn't reappear after restart
  if M_ref.session_enabled then
    state.delete_workspace_state(workspace_name)
    wezterm.log_info("workspace_manager: deleted saved state for: " .. workspace_name)
  end
end

local function do_rename_workspace(old_name, new_name, window, pane)
  if not new_name or new_name == "" or new_name == old_name then
    return
  end

  local new_normalized = helpers.normalize_workspace_name(new_name)

  -- Check if target name already exists (merge scenario)
  local name_exists = false
  for _, ws in ipairs(mux.get_workspace_names()) do
    local ws_normalized = helpers.normalize_workspace_name(ws)
    if ws_normalized == new_normalized then
      name_exists = true
      break
    end
  end

  if name_exists then
    helpers.notify(window, "Workspace Rename", 'Merging "' .. old_name .. '" into existing "' .. new_normalized .. '"', 3000)
    -- For merge: move windows to existing workspace
    for _, mux_win in ipairs(mux.all_windows()) do
      if mux_win:get_workspace() == old_name then
        mux_win:set_workspace(new_normalized)
      end
    end
  else
    -- Only rename in mux if the workspace actually exists there (saved-only workspaces don't)
    local old_exists_in_mux = false
    for _, ws in ipairs(mux.get_workspace_names()) do
      if ws == old_name then
        old_exists_in_mux = true
        break
      end
    end
    if old_exists_in_mux then
      mux.rename_workspace(old_name, new_normalized)
    end
  end

  -- Update history
  local old_normalized = helpers.normalize_workspace_name(old_name)
  if wezterm.GLOBAL.workspace_access_times then
    local old_time = wezterm.GLOBAL.workspace_access_times[old_normalized]
    wezterm.GLOBAL.workspace_access_times[old_normalized] = nil
    wezterm.GLOBAL.workspace_access_times[new_normalized] = old_time or os.time()
    history.save(wezterm.GLOBAL.workspace_access_times)
  end

  -- Rename state file if it exists
  if M_ref.session_enabled then
    state.rename_workspace_state(old_name, new_normalized)
  end

  helpers.notify(window, "Workspace Rename", 'Renamed "' .. old_name .. '" to "' .. new_normalized .. '"')
  wezterm.emit("workspace_manager.workspace_switcher.renamed", window, pane, old_name, new_normalized)
end

-- ============================================================================
-- Exported Actions
-- ============================================================================

function mod.workspace_switcher()
  return wezterm.action_callback(function(window, pane)
    local workspace_choices
    if M_ref.workspace_switcher_sort == "alphabetical" then
      workspace_choices = data.get_workspace_choices_alphabetical()
    else
      workspace_choices = data.get_workspace_choices()
    end

    local workspace_normalized_set = {}
    for _, choice in ipairs(workspace_choices) do
      workspace_normalized_set[choice.normalized] = true
    end

    local custom_choices, is_zoxide, label_overrides = data.get_custom_choices(workspace_normalized_set)

    -- Get workspace counts if format is enabled
    local workspace_counts = nil
    if M_ref.workspace_count_format then
      workspace_counts = data.get_workspace_counts()
    end

    local current_workspace = window:active_workspace()
    local current_normalized = helpers.normalize_workspace_name(current_workspace)
    local current_display = label_overrides[current_workspace] or current_normalized

    -- Track which ids are live workspaces, saved (disk-only) workspaces, or custom entries
    local existing_workspace_ids = {}
    local saved_workspace_ids = {}
    for _, choice in ipairs(workspace_choices) do
      if choice.is_saved then
        saved_workspace_ids[choice.id] = true
      else
        existing_workspace_ids[choice.id] = true
      end
    end

    -- Map custom entry ids back to their full choice objects (needed in callback to resolve name/path)
    local custom_entry_map = {}
    for _, choice in ipairs(custom_choices) do
      custom_entry_map[choice.id] = choice
    end

    local filter_fn
    if type(M_ref.filter_choices) == "table" then
      local set = {}
      for _, p in ipairs(M_ref.filter_choices) do
        set[helpers.normalize_workspace_name(p)] = true
      end
      filter_fn = function(choice)
        if choice.is_workspace then return true end
        return set[choice.normalized] or false
      end
    elseif type(M_ref.filter_choices) == "function" then
      filter_fn = M_ref.filter_choices
    end

    local all_choices = {}
    for _, choice in ipairs(workspace_choices) do
      local is_current = (choice.id == current_workspace)

      -- Skip current workspace if configured to hide it
      if is_current and not M_ref.show_current_workspace_in_switcher then
        -- skip
      elseif filter_fn and not filter_fn(choice) then
        -- skip: user filter rejected this entry
      else
        local count_suffix = ""
        if workspace_counts and workspace_counts[choice.id] then
          count_suffix = data.format_counts(workspace_counts[choice.id], M_ref.workspace_count_format)
        end

        local display_label = label_overrides[choice.id] or choice.label
        local category = is_current and "current" or "workspace"
        local ws_icon = M_ref.workspace_icon or "󱂬  "
        local icon = is_current and (M_ref.workspace_icon_current or ws_icon) or ws_icon
        local label = theme.build_switcher_label(icon, display_label, count_suffix, category)
        table.insert(all_choices, { id = choice.id, label = label })
      end
    end
    for _, choice in ipairs(custom_choices) do
      if not filter_fn or filter_fn(choice) then
        table.insert(all_choices, {
          id = choice.id,
          label = theme.build_switcher_label(M_ref.entry_icon or "  ", choice.label, "", "entry"),
        })
      end
    end

    if #all_choices == 0 then
      helpers.notify(window, "Workspace", "No other workspaces available")
      return
    end

    -- Build description with optional current workspace hint and action key hints
    local description
    local fuzzy_description
    local hints_infix = ""  -- goes between the workspace hint and Esc/Switch-to
    if M_ref.show_switcher_hints then
      local hints = mod.build_switcher_hints(" ")
      if hints ~= "" then hints_infix = " " .. hints .. " |" end
    end
    if M_ref.show_current_workspace_hint then
      description = wezterm.format({
        theme.fg(theme.get_color("prompt_accent")),
        { Text = current_display },
        theme.fg(theme.get_color("muted")),
        { Text = " |" .. hints_infix .. " Esc=cancel" },
      })
      fuzzy_description = wezterm.format({
        theme.fg(theme.get_color("prompt_accent")),
        { Text = current_display },
        theme.fg(theme.get_color("muted")),
        { Text = " |" .. hints_infix .. " Switch to: " },
      })
    else
      description = wezterm.format({
        theme.fg(theme.get_color("muted")),
        { Text = "Enter=switch |" .. hints_infix .. " Esc=cancel" },
      })
      fuzzy_description = wezterm.format({
        theme.fg(theme.get_color("muted")),
        { Text = "Switch to: " },
      })
    end

    -- Activate the key table so Ctrl+D/N/P/R are intercepted while the overlay is open
    switcher_state.pending_action = nil
    window:perform_action(
      act.ActivateKeyTable { name = "workspace_switcher_actions", one_shot = false },
      pane
    )
    wezterm.emit("workspace_manager.switcher.opened", window, pane)

    window:perform_action(
      act.InputSelector {
        title = "Workspace Switcher",
        description = description,
        fuzzy = M_ref.start_in_fuzzy_mode,
        fuzzy_description = fuzzy_description,
        choices = all_choices,
        action = wezterm.action_callback(function(win, p, id, label)
          local pending = switcher_state.pending_action
          switcher_state.pending_action = nil

          -- Cancelled (Escape or click-outside)
          if not id and not label then
            wezterm.emit("workspace_manager.switcher.canceled", win, p)
            return
          end

          if pending == "delete" then
            wezterm.log_info("workspace_manager: switcher delete action, id=" .. tostring(id))
            if id == win:active_workspace() then
              wezterm.log_warn("workspace_manager: switcher blocked delete of active workspace")
              helpers.notify(win, "Workspace", "Cannot delete active workspace")
            elseif saved_workspace_ids[id] then
              -- Saved-only workspace: no live panes to kill, just remove state + history
              wezterm.log_info("workspace_manager: deleting saved-only workspace: " .. id)
              local normalized = helpers.normalize_workspace_name(id)
              if wezterm.GLOBAL.workspace_access_times then
                wezterm.GLOBAL.workspace_access_times[normalized] = nil
                history.save(wezterm.GLOBAL.workspace_access_times)
              end
              if M_ref.session_enabled then
                state.delete_workspace_state(id)
              end
              wezterm.emit("workspace_manager.workspace_switcher.deleted", win, p, id)
            elseif existing_workspace_ids[id] then
              do_close_workspace(id, win, p)
              wezterm.emit("workspace_manager.workspace_switcher.deleted", win, p, id)
            else
              helpers.notify(win, "Workspace", "Cannot delete: not a workspace")
            end
            -- Re-open switcher after delete so user can continue
            wezterm.time.call_after(0.1, function()
              win:perform_action(mod.workspace_switcher(), p)
            end)

          elseif pending == "rename" then
            if not existing_workspace_ids[id] and not saved_workspace_ids[id] then
              helpers.notify(win, "Workspace", "Cannot rename: not a workspace")
              wezterm.time.call_after(0.1, function()
                win:perform_action(mod.workspace_switcher(), p)
              end)
            else
              win:perform_action(
                act.PromptInputLine {
                  description = wezterm.format {
                    theme.fg(theme.get_color("prompt_accent")),
                    { Text = "Renaming: " .. helpers.normalize_workspace_name(id) },
                    theme.fg(theme.get_color("muted")),
                    { Text = " | Enter new name:" },
                  },
                  action = wezterm.action_callback(function(inner_win, inner_p, line)
                    if line and line ~= "" then
                      do_rename_workspace(id, line, inner_win, inner_p)
                    end
                    -- Re-open switcher whether rename succeeded or was cancelled
                    wezterm.time.call_after(0.1, function()
                      inner_win:perform_action(mod.workspace_switcher(), inner_p)
                    end)
                  end),
                },
                p
              )
            end

          elseif pending == "new" then
            win:perform_action(
              act.PromptInputLine {
                description = wezterm.format(theme.build_heading("Enter name for new workspace:")),
                action = wezterm.action_callback(function(inner_win, inner_p, line)
                  if line and line ~= "" then
                    local old_workspace = inner_win:active_workspace()
                    if M_ref.session_enabled and old_workspace and not state.is_excluded_workspace(old_workspace) then
                      state.save_workspace_state(old_workspace, inner_win)
                    end
                    if old_workspace then
                      local old_mux_window = data.get_current_mux_window(old_workspace)
                      wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, inner_p, old_workspace, line)
                    end
                    inner_win:perform_action(act.SwitchToWorkspace { name = line }, inner_p)
                    history.update_access_time(line)
                    local new_mux_window = data.get_current_mux_window(line)
                    if M_ref.session_enabled then
                      state.restore_workspace_state(line, new_mux_window)
                    end
                    wezterm.emit("workspace_manager.workspace_switcher.created", new_mux_window, inner_p, line)
                  else
                    wezterm.time.call_after(0.1, function()
                      inner_win:perform_action(mod.workspace_switcher(), inner_p)
                    end)
                  end
                end),
              },
              p
            )

          elseif pending == "new_at_path" then
            win:perform_action(
              act.PromptInputLine {
                description = wezterm.format(theme.build_heading("Enter path for new workspace:")),
                action = wezterm.action_callback(function(inner_win, inner_p, line)
                  if line and line ~= "" then
                    local workspace_name, expanded_path = helpers.get_workspace_name_and_path(line)

                    local function do_switch()
                      local old_workspace = inner_win:active_workspace()
                      if M_ref.session_enabled and old_workspace and not state.is_excluded_workspace(old_workspace) then
                        state.save_workspace_state(old_workspace, inner_win)
                      end
                      if old_workspace then
                        local old_mux_window = data.get_current_mux_window(old_workspace)
                        wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, inner_p, old_workspace, workspace_name)
                      end
                      inner_win:perform_action(
                        act.SwitchToWorkspace { name = workspace_name, spawn = { cwd = expanded_path } },
                        inner_p
                      )
                      history.update_access_time(workspace_name)
                      if is_zoxide then
                        wezterm.run_child_process({ M_ref.zoxide_path, "add", "--", line })
                      end
                      local new_mux_window = data.get_current_mux_window(workspace_name)
                      if M_ref.session_enabled then
                        state.restore_workspace_state(workspace_name, new_mux_window)
                      end
                      wezterm.emit("workspace_manager.workspace_switcher.created", new_mux_window, inner_p, workspace_name, expanded_path)
                    end

                    if helpers.directory_exists(expanded_path) then
                      do_switch()
                    else
                      inner_win:perform_action(
                        act.InputSelector {
                          title = "Create directory",
                          description = wezterm.format(theme.build_heading("Directory does not exist: "))
                            .. wezterm.format { theme.fg(theme.get_color("prompt_accent")), { Text = helpers.normalize_workspace_name(line) } }
                            .. wezterm.format(theme.build_heading(". Create it?")),
                          fuzzy = false,
                          choices = {
                            { id = "yes", label = "Yes" },
                            { id = "no",  label = "No" },
                          },
                          action = wezterm.action_callback(function(confirm_win, confirm_p, id, _label)
                            if id == "yes" then
                              local mkdir_ok, _, mkdir_err = helpers.create_directory(expanded_path)
                              if mkdir_ok then
                                do_switch()
                              else
                                wezterm.log_warn("workspace_manager: mkdir failed for " .. expanded_path .. ": " .. tostring(mkdir_err))
                                helpers.notify(confirm_win, "Workspace", "Failed to create directory: " .. tostring(mkdir_err), 4000)
                              end
                            end
                          end),
                        },
                        inner_p
                      )
                    end
                  else
                    wezterm.time.call_after(0.1, function()
                      inner_win:perform_action(mod.workspace_switcher(), inner_p)
                    end)
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
              if M_ref.session_enabled and old_workspace and not state.is_excluded_workspace(old_workspace) then
                state.save_workspace_state(old_workspace, win)
              end
              if old_workspace then
                local old_mux_window = data.get_current_mux_window(old_workspace)
                wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, p, old_workspace, id)
              end
              win:perform_action(act.SwitchToWorkspace({ name = id }), p)
              history.update_access_time(id)
              local new_mux_window = data.get_current_mux_window(id)
              -- Restore focused window order from saved state if available.
              if M_ref.session_enabled and not state.is_excluded_workspace(id) then
                local saved = state.load_workspace_state(id)
                if saved and saved.window_states then
                  -- Find and focus the window that was focused at save time.
                  local all_mux_wins = wezterm.mux.all_windows()
                  for _, ws in ipairs(saved.window_states) do
                    if ws.is_focused and ws.window_id then
                      for _, mux_win in ipairs(all_mux_wins) do
                        if mux_win:get_workspace() == id and mux_win:window_id() == ws.window_id then
                          local ok, gui_win = pcall(function() return mux_win:gui_window() end)
                          if ok and gui_win then gui_win:focus() end
                          break
                        end
                      end
                      break
                    end
                  end
                end
              end
              wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, p, id)

            elseif is_saved_workspace then
              local old_workspace = win:active_workspace()
              if M_ref.session_enabled and old_workspace and not state.is_excluded_workspace(old_workspace) then
                state.save_workspace_state(old_workspace, win)
              end
              if old_workspace then
                local old_mux_window = data.get_current_mux_window(old_workspace)
                wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, p, old_workspace, id)
              end
              win:perform_action(act.SwitchToWorkspace({ name = id }), p)
              history.update_access_time(id)
              local new_mux_window = data.get_current_mux_window(id)
              state.restore_workspace_state(id, new_mux_window)
              wezterm.emit("workspace_manager.workspace_switcher.created", new_mux_window, p, id)

            else
              -- Custom/zoxide entry: create new workspace at path or with name
              local entry = custom_entry_map[id]
              local workspace_name, expanded_path
              if entry and entry.name then
                -- Custom provider entry: use explicit name and optional path
                workspace_name = entry.name
                if entry.has_path then
                  _, expanded_path = helpers.normalize_workspace_name(entry.path)
                end
              else
                -- Zoxide entry: derive workspace name and path from the raw path id
                workspace_name, expanded_path = helpers.get_workspace_name_and_path(id)
              end
              local old_workspace = win:active_workspace()
              if M_ref.session_enabled and old_workspace and not state.is_excluded_workspace(old_workspace) then
                state.save_workspace_state(old_workspace, win)
              end
              if old_workspace then
                local old_mux_window = data.get_current_mux_window(old_workspace)
                wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, p, old_workspace, workspace_name)
              end
              win:perform_action(
                act.SwitchToWorkspace({ name = workspace_name, spawn = { cwd = expanded_path or wezterm.home_dir } }),
                p
              )
              history.update_access_time(workspace_name)
              if is_zoxide then
                wezterm.run_child_process({ M_ref.zoxide_path, "add", "--", id })
              end
              local new_mux_window = data.get_current_mux_window(workspace_name)
              if M_ref.session_enabled then
                state.restore_workspace_state(workspace_name, new_mux_window)
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

function mod.switch_to_previous_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local previous_workspace = wezterm.GLOBAL.previous_workspace

    if current_workspace == previous_workspace or previous_workspace == nil then
      return
    end

    -- Save current workspace state before switching
    if M_ref.session_enabled and not state.is_excluded_workspace(current_workspace) then
      state.save_workspace_state(current_workspace, window)
    end

    wezterm.GLOBAL.previous_workspace = current_workspace

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = data.get_current_mux_window(current_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, pane, current_workspace, previous_workspace)

    window:perform_action(act.SwitchToWorkspace({ name = previous_workspace }), pane)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = data.get_current_mux_window(previous_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, pane, previous_workspace)
  end)
end

function mod.next_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local choices = data.get_workspace_cycle_order()

    if #choices <= 1 then
      helpers.notify(window, "Workspace", "No other workspaces available")
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
    if M_ref.session_enabled and not state.is_excluded_workspace(old_workspace) then
      state.save_workspace_state(old_workspace, window)
    end

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = data.get_current_mux_window(old_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, pane, old_workspace, next_workspace)

    window:perform_action(act.SwitchToWorkspace({ name = next_workspace }), pane)
    history.update_access_time(next_workspace)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = data.get_current_mux_window(next_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, pane, next_workspace)
  end)
end

function mod.previous_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local choices = data.get_workspace_cycle_order()

    if #choices <= 1 then
      helpers.notify(window, "Workspace", "No other workspaces available")
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
    if M_ref.session_enabled and not state.is_excluded_workspace(old_workspace) then
      state.save_workspace_state(old_workspace, window)
    end

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = data.get_current_mux_window(old_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.switching", old_mux_window, pane, old_workspace, prev_workspace)

    window:perform_action(act.SwitchToWorkspace({ name = prev_workspace }), pane)
    history.update_access_time(prev_workspace)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = data.get_current_mux_window(prev_workspace)
    wezterm.emit("workspace_manager.workspace_switcher.selected", new_mux_window, pane, prev_workspace)
  end)
end

function mod.save_workspace()
  return wezterm.action_callback(function(window, pane)
    if not M_ref.session_enabled then
      helpers.notify(window, "Workspace", "Session persistence is not enabled")
      return
    end
    local workspace = window:active_workspace()
    if state.is_excluded_workspace(workspace) then
      helpers.notify(window, "Workspace", "Workspace is excluded from session saves")
      return
    end
    state.save_workspace_state(workspace, window)
    helpers.notify(window, "Workspace", "Saved: " .. helpers.normalize_workspace_name(workspace))
  end)
end

return mod
