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
    -- Use built-in rename function
    mux.rename_workspace(old_name, new_normalized)
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

    local all_choices = {}
    for _, choice in ipairs(workspace_choices) do
      local is_current = (choice.id == current_workspace)

      -- Skip current workspace if configured to hide it
      if is_current and not M_ref.show_current_workspace_in_switcher then
        -- skip
      else
        local count_suffix = ""
        if workspace_counts and workspace_counts[choice.id] then
          count_suffix = data.format_counts(workspace_counts[choice.id], M_ref.workspace_count_format)
        end

        local display_label = label_overrides[choice.id] or choice.label
        local label = theme.build_switcher_label("󱂬  ", display_label, count_suffix, is_current)
        table.insert(all_choices, { id = choice.id, label = label })
      end
    end
    for _, choice in ipairs(custom_choices) do
      table.insert(all_choices, {
        id = choice.id,
        label = theme.build_switcher_label("  ", choice.label, "", false),
      })
    end

    if #all_choices == 0 then
      helpers.notify(window, "Workspace", "No other workspaces available")
      return
    end

    -- Build description with optional current workspace hint
    local description
    local fuzzy_description
    if M_ref.show_current_workspace_hint then
      description = wezterm.format({
        theme.fg(theme.get_color("highlight")),
        { Text = "Current: " .. current_display },
        theme.fg(theme.get_color("muted")),
        { Text = " | ^D=del ^N=new ^P=path ^R=rename | Esc=cancel" },
      })
      fuzzy_description = wezterm.format({
        theme.fg(theme.get_color("highlight")),
        { Text = "Current: " .. current_display },
        theme.fg(theme.get_color("muted")),
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
        fuzzy = M_ref.start_in_fuzzy_mode,
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
            else
              do_close_workspace(id, win, p)
            end
            -- Re-open switcher after delete so user can continue
            wezterm.time.call_after(0.1, function()
              win:perform_action(mod.workspace_switcher(), p)
            end)

          elseif pending == "rename" then
            win:perform_action(
              act.PromptInputLine {
                description = wezterm.format {
                  theme.fg(theme.get_color("highlight")),
                  { Text = "Renaming: " .. helpers.normalize_workspace_name(id) },
                  theme.fg(theme.get_color("muted")),
                  { Text = " | Enter new name:" },
                },
                action = wezterm.action_callback(function(inner_win, inner_p, line)
                  if line and line ~= "" then
                    do_rename_workspace(id, line, inner_win, inner_p)
                    -- Re-open switcher after rename so user can continue
                    wezterm.time.call_after(0.1, function()
                      inner_win:perform_action(mod.workspace_switcher(), inner_p)
                    end)
                  end
                end),
              },
              p
            )

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
                            .. wezterm.format { theme.fg(theme.get_color("highlight")), { Text = helpers.normalize_workspace_name(line) } }
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

return mod
