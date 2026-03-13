local wezterm = require("wezterm")

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

-- Load submodules
local theme      = require("theme")
local helpers    = require("helpers")
local history    = require("history")
local state      = require("state")
local data       = require("data")
local actions    = require("actions")
local config_mod = require("config")

-- Wire dependencies (topological order)
theme.setup(M)
helpers.setup(M)
history.setup(M, { helpers = helpers })
state.setup(M, { helpers = helpers, history = history })
data.setup(M, { helpers = helpers, state = state })
actions.setup(M, { theme = theme, helpers = helpers, history = history, state = state, data = data })
config_mod.setup(M, { theme = theme, helpers = helpers, history = history, state = state, actions = actions })

-- Public API
M.workspace_switcher          = actions.workspace_switcher
M.switch_to_previous_workspace = actions.switch_to_previous_workspace
M.next_workspace              = actions.next_workspace
M.previous_workspace          = actions.previous_workspace
M.apply_to_config             = config_mod.apply_to_config

return M
