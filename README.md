# Workspace Manager for Wezterm

> Navigate projects effortlessly with smart workspace switching and keyboard-driven navigation

A powerful workspace management plugin for Wezterm featuring:
- Smart workspace switching with fuzzy search and recency sorting
- Keyboard navigation (cycle, toggle, quick switch)
- Zoxide integration for directory history
- Full workspace lifecycle management (create, close, rename)
- **Built-in session persistence** — workspaces survive WezTerm restarts with full layout restoration

## Installation

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Load the plugin
local workspace_manager = wezterm.plugin.require("https://github.com/ryanmsnyder/workspace-manager.wezterm")

-- Apply to config (adds default keybindings)
workspace_manager.apply_to_config(config)

return config
```

## Requirements

- [Wezterm](https://wezfurlong.org/wezterm/) (version 20230408-112425-69ae8472 or later for InputSelector)
- [zoxide](https://github.com/ajeetdsouza/zoxide) (optional, for directory history integration)
- A `LEADER` key configured in your wezterm config

## Keybindings

When using `apply_to_config()`, the following default keybindings are added:

| Key | Action | Description |
|-----|--------|-------------|
| `LEADER + s` | Switch workspace | Main switcher with recency ordering and zoxide integration |
| `LEADER + n` | New workspace | Prompt for a name to create a new workspace |
| `LEADER + Shift-N` | New workspace at path | Prompt for a path to create a workspace rooted there |
| `LEADER + x` | Close workspace | Select and close a workspace |
| `LEADER + r` | Rename workspace | Rename the current workspace |
| `LEADER + Shift-S` | Previous workspace | Switch to the previously active workspace (Alt-Tab toggle) |
| `CTRL + ]` | Next workspace | Cycle to the next workspace in alphabetical order |
| `CTRL + [` | Previous workspace | Cycle to the previous workspace in alphabetical order |

**Note:** Workspace cycling (CTRL+] and CTRL+[) always uses case-insensitive alphabetical ordering to provide predictable, stable navigation. This prevents unexpected behavior where the workspace list would re-sort during cycling. The workspace switcher (LEADER+s) uses recency-based sorting by default, but can be configured to use alphabetical sorting via the `workspace_switcher_sort` option.

## Custom Keybindings

If you prefer to set up your own keybindings instead of using `apply_to_config()`:

```lua
local workspace_manager = wezterm.plugin.require("https://github.com/ryanmsnyder/workspace-manager.wezterm")

config.keys = {
  -- Your custom keybindings
  {
    key = "w",
    mods = "CTRL|SHIFT",
    action = workspace_manager.switch_workspace(),
  },
  {
    key = "n",
    mods = "CTRL|SHIFT",
    action = workspace_manager.new_workspace(),
  },
  {
    key = "q",
    mods = "CTRL|SHIFT",
    action = workspace_manager.close_workspace(),
  },
  {
    key = "r",
    mods = "CTRL|SHIFT",
    action = workspace_manager.rename_workspace(),
  },
  {
    key = "p",
    mods = "CTRL|SHIFT",
    action = workspace_manager.switch_to_previous_workspace(),
  },
  {
    key = "]",
    mods = "CTRL",
    action = workspace_manager.next_workspace(),
  },
  {
    key = "[",
    mods = "CTRL",
    action = workspace_manager.previous_workspace(),
  },
}
```

## API

### Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `wezterm_path` | string | Auto-detected | Path to wezterm executable (only needed if auto-detection fails) |
| `zoxide_path` | string | `"zoxide"` | Path to zoxide binary |
| `show_current_workspace_in_switcher` | boolean | `false` | Show current workspace in the switcher list |
| `show_current_workspace_hint` | boolean | `true` | Show current workspace name in the switcher description |
| `start_in_fuzzy_mode` | boolean | `true` | Start switcher in fuzzy search mode (false for positional shortcuts) |
| `notifications_enabled` | boolean | `false` | Enable toast notifications (requires code-signed wezterm on macOS) |
| `workspace_count_format` | string | `"compact"` | Display workspace counts: `nil` (disabled), `"compact"` (2w 3t 5p), or `"full"` (2 wins, 3 tabs, 5 panes) |
| `use_basename_for_workspace_names` | boolean | `false` | Use directory basename instead of full path (falls back for duplicates) |
| `workspace_switcher_sort` | string | `"recency"` | Sort order: `"recency"` (most recent first) or `"alphabetical"` |

**Session persistence options** (requires `resurrect_enabled = true`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `resurrect_enabled` | boolean | `false` | Enable automatic workspace state save/restore |
| `resurrect_periodic_save_interval` | number | `600` | Seconds between periodic saves (`nil` to disable) |
| `resurrect_periodic_save_all` | boolean | `false` | Periodic save: `true` = all workspaces, `false` = active workspace only |
| `resurrect_max_scrollback_lines` | number | `3500` | Max scrollback lines to capture per pane |
| `resurrect_exclude_workspaces` | table | `{"default"}` | Workspace names to never save or restore |
| `resurrect_state_dir` | string | `nil` | Override state directory (default: `~/.local/share/wezterm/workspace_state/`) |
| `resurrect_on_pane_restore` | function | `nil` | Custom per-pane restore callback (default: replays processes / injects scrollback) |
| `resurrect_restore_on_startup` | boolean | `false` | Automatically restore the most recently used workspace when WezTerm starts |

### Actions

All actions return a Wezterm action that can be used in keybindings:

- `workspace_manager.switch_workspace()` - Opens the main workspace switcher UI
- `workspace_manager.new_workspace()` - Prompts for a name to create a new workspace
- `workspace_manager.new_workspace_at_path()` - Prompts for a path to create a workspace rooted there
- `workspace_manager.close_workspace()` - Opens a selector to close a workspace
- `workspace_manager.rename_workspace()` - Prompts for a new name for the current workspace
- `workspace_manager.switch_to_previous_workspace()` - Switches to the previously active workspace (Alt-Tab toggle behavior)
- `workspace_manager.next_workspace()` - Cycles to the next workspace in alphabetical order (with wrapping)
- `workspace_manager.previous_workspace()` - Cycles to the previous workspace in alphabetical order (with wrapping)

### `apply_to_config(config)`

Adds the default keybindings and event handlers to your config.

## Features

### Workspace Switcher

The main switcher (`LEADER + s`) shows:

1. **Active workspaces** (sorted by recency or alphabetically, marked with 󱂬 icon)
2. **Saved workspaces** from previous sessions (also marked with 󱂬 icon, mixed in by recency/alphabetical — requires `resurrect_enabled = true`)
3. **Zoxide directory history** (marked with  icon)

Use fuzzy search by pressing `/` to filter the list.

### Recency Persistence

Workspace access times are saved to `~/.local/share/wezterm/workspace_history.json` and persist across restarts.

### Path Normalization

All workspace names are normalized to use `~` for the home directory. This prevents duplicates when switching between `~/projects` and `/Users/you/projects`.

### Workspace Closing

- Cannot close the currently active workspace
- Removes the workspace from the recency history

### Workspace Renaming

- Renames the current workspace
- If the new name matches an existing workspace, windows are merged
- Access time is preserved after rename

## Session Persistence

workspace-manager includes built-in session persistence — workspace layouts (panes, tabs, splits, working directories, scrollback) are automatically saved and restored across WezTerm restarts. No external plugins required.

### Quick Setup

```lua
local workspace_manager = wezterm.plugin.require("https://github.com/ryanmsnyder/workspace-manager.wezterm")

workspace_manager.resurrect_enabled = true  -- enable session persistence
workspace_manager.resurrect_restore_on_startup = true  -- optional: restore last workspace on launch

workspace_manager.apply_to_config(config)
```

That's it. With `resurrect_enabled = true`:

- **State is saved automatically** when you switch away from a workspace
- **Previously-active workspaces appear in the switcher** after restarting WezTerm, sorted by recency/alphabetical alongside live ones
- **State is restored** when you select a saved workspace (tabs, pane splits, working directories, scrollback text)
- **Periodic auto-save** runs every 10 minutes as a crash safety net
- **Closing a workspace** deletes its saved state so it won't reappear

With `resurrect_restore_on_startup = true`, WezTerm also opens directly into your most recently used workspace on launch instead of the default workspace.

### State Location

State files are stored at `~/.local/share/wezterm/workspace_state/<workspace-name>.json`.

### How It Works

- **Save on switch**: Before switching away from a workspace, its full layout is captured — all windows, tabs, pane splits, working directories, and scrollback text — and written to disk
- **Lazy restore**: After a restart, saved workspace names are read from the state directory and shown in the switcher alongside live workspaces. The full layout is only restored when you actually select a workspace (fast startup)
- **Startup restore**: With `resurrect_restore_on_startup = true`, the most recently used workspace (by access time) is automatically restored when WezTerm starts. If no saved state exists, WezTerm opens normally
- **In-memory workspaces**: Switching between workspaces that are already running is instant — no restoration needed, they're already in memory
- **Default workspace excluded**: The `"default"` workspace is never saved or restored by default

### Events Reference

The plugin emits events you can hook into for custom behavior:

| Event | When | Parameters | Purpose |
|-------|------|-----------|---------|
| `workspace_switcher.switching` | **Before** workspace switch | `mux_window, pane, old_workspace, new_workspace` | Fires before every switch (built-in save happens here) |
| `workspace_switcher.created` | **After** creating new workspace | `mux_window, pane, workspace_name, path` | Fires after a new workspace is created and restored |
| `workspace_switcher.selected` | **After** switching to existing workspace | `mux_window, pane, workspace_name` | Fires after switching to a live in-memory workspace |

**Note**: All workspace events pass `MuxWindow` objects as the first parameter (consistent with [smart_workspace_switcher](https://github.com/MLFlexer/smart_workspace_switcher.wezterm) API).

### Using External Resurrect Plugin Instead

If you prefer to use [MLFlexer/resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm) directly (e.g., to use its fuzzy loader, encryption, or window/tab-level saves), keep `resurrect_enabled = false` and wire up the events manually:

```lua
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")
local workspace_manager = wezterm.plugin.require("https://github.com/ryanmsnyder/workspace-manager.wezterm")

-- Save old workspace state BEFORE switching
wezterm.on("workspace_manager.workspace_switcher.switching", function(mux_window, pane, old_workspace, new_workspace)
  if old_workspace and old_workspace ~= "default" and old_workspace ~= new_workspace then
    local state = resurrect.workspace_state.get_workspace_state()
    resurrect.state_manager.save_state(state, old_workspace)
  end
end)

-- Restore workspace state when creating a new workspace from zoxide
wezterm.on("workspace_manager.workspace_switcher.created", function(mux_window, pane, workspace_name, path)
  local state = resurrect.state_manager.load_state(workspace_name, "workspace")
  if state then
    resurrect.workspace_state.restore_workspace(state, {
      window = mux_window,
      relative = true,
      on_pane_restore = resurrect.tab_state.default_on_pane_restore,
    })
  end
end)
```

## Troubleshooting

### Wezterm CLI not found

The plugin auto-detects the wezterm executable path using `wezterm.executable_dir`. If auto-detection fails (rare), you can manually set the path:

```lua
workspace_manager.wezterm_path = "/Applications/WezTerm.app/Contents/MacOS/wezterm"
```

Common paths:
- **macOS (App):** `/Applications/WezTerm.app/Contents/MacOS/wezterm`
- **macOS (Homebrew):** `/opt/homebrew/bin/wezterm`
- **Linux:** `/usr/bin/wezterm` or `/usr/local/bin/wezterm`

### Zoxide not found

If you get errors about zoxide not being found, set the full path:

```lua
workspace_manager.zoxide_path = "/usr/local/bin/zoxide"
-- or for Nix users:
workspace_manager.zoxide_path = "/etc/profiles/per-user/yourusername/bin/zoxide"
```

### No workspaces shown

Make sure you have zoxide installed and have some directory history. You can also create workspaces manually using `LEADER + n`.

### Icons not displaying

The plugin uses Nerd Font icons. Make sure your terminal font includes Nerd Font symbols.

### Notifications not working

Toast notifications are disabled by default. To enable them:

```lua
workspace_manager.notifications_enabled = true
```

**Note:** On macOS, toast notifications require a code-signed application. If you're running WezTerm built from source, installed via Nix, or using a non-signed build, notifications will not work. Use the official signed release from [WezTerm releases](https://github.com/wez/wezterm/releases) if you want notifications.

## Acknowledgments

- Zoxide integration inspired by [MLFlexer/smart_workspace_switcher.wezterm](https://github.com/MLFlexer/smart_workspace_switcher.wezterm)
- Session persistence powered by code from [MLFlexer/resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm) (MIT licensed)

## License

MIT
