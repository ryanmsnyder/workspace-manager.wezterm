local wezterm = require("wezterm")
local mux = wezterm.mux

local M_ref   -- reference to plugin config table (set via setup)
local theme   -- set via setup
local helpers -- set via setup
local history -- set via setup
local state   -- set via setup
local actions -- set via setup

local mod = {}

function mod.setup(plugin, deps)
  M_ref   = plugin
  theme   = deps.theme
  helpers = deps.helpers
  history = deps.history
  state   = deps.state
  actions = deps.actions
end

function mod.get_switcher_legend()
  return wezterm.format({
    theme.fg(theme.get_color("muted")),
    { Text = "  ^D=del  ^N=new  ^P=path  ^R=rename  Esc=cancel" },
  })
end

function mod.apply_to_config(config)
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
  if M_ref.session_enabled then
    -- Apply max scrollback lines config
    local pane_tree_mod = require("session.pane_tree")
    pane_tree_mod.max_nlines = M_ref.session_max_scrollback_lines

    -- Periodic save timer
    if M_ref.session_periodic_save_interval then
      local function periodic_save()
        wezterm.time.call_after(M_ref.session_periodic_save_interval, function()
          if M_ref.session_periodic_save_all then
            for _, ws_name in ipairs(mux.get_workspace_names()) do
              if not state.is_excluded_workspace(ws_name) then
                state.save_workspace_state(ws_name)
              end
            end
          else
            local active = mux.get_active_workspace()
            if active and not state.is_excluded_workspace(active) then
              state.save_workspace_state(active)
            end
          end
          periodic_save()
        end)
      end
      periodic_save()
    end

    -- Restore most recently used workspace on startup
    if M_ref.session_restore_on_startup then
      wezterm.on("gui-startup", function(_cmd)
        local workspace_name = state.get_most_recent_saved_workspace()
        if not workspace_name then return end
        local ws_state = state.load_workspace_state(workspace_name)
        if not ws_state then return end
        local _, expanded = helpers.normalize_workspace_name(workspace_name)

        local ws = ws_state.window_states and ws_state.window_states[1]
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
          state.restore_workspace_state(workspace_name, window, {
            relative = true,
            close_open_panes = true,
            resize_window = false,
          })
          history.update_access_time(workspace_name)
          wezterm.GLOBAL.last_focused_workspace = workspace_name
        end

        state.wait_for_stable_window(window, 0.10, 2, 15, function()
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
            state.wait_for_stable_window(window, 0.10, 2, 8, function()
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
    actions.switcher_keymap_cancel("Enter"),  -- pop key table, then forward Enter to select
    actions.switcher_keymap("d", "CTRL", "delete"),
    actions.switcher_keymap("n", "CTRL", "new"),
    actions.switcher_keymap("p", "CTRL", "new_at_path"),
    actions.switcher_keymap("r", "CTRL", "rename"),
    actions.switcher_keymap_cancel("Escape"),
  }

  -- Default keybindings (users can override by setting their own keys)
  local keys = config.keys or {}

  table.insert(keys, {
    key = "s",
    mods = "LEADER",
    action = M_ref.workspace_switcher(),
  })

  table.insert(keys, {
    key = "S",
    mods = "LEADER",
    action = M_ref.switch_to_previous_workspace(),
  })

  table.insert(keys, {
    key = "]",
    mods = "CTRL",
    action = M_ref.next_workspace(),
  })

  table.insert(keys, {
    key = "[",
    mods = "CTRL",
    action = M_ref.previous_workspace(),
  })

  config.keys = keys
end

return mod
