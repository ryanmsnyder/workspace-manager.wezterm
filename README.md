# Workspace Manager for Wezterm

> Navigate projects effortlessly with smart workspace switching and keyboard-driven navigation

A powerful workspace management plugin for Wezterm featuring:
- Unified workspace switcher with fuzzy search, recency sorting, and in-overlay actions
- Keyboard navigation (cycle, toggle, quick switch)
- Zoxide integration for directory history
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
| `LEADER + s` | Workspace switcher | Open the unified switcher |
| `LEADER + Shift-S` | Previous workspace | Switch to the previously active workspace (Alt-Tab toggle) |
| `CTRL + ]` | Next workspace | Cycle to the next workspace in alphabetical order |
| `CTRL + [` | Previous workspace | Cycle to the previous workspace in alphabetical order |

**While the switcher is open**, the following keys are available:

| Key | Action |
|-----|--------|
| `Enter` | Switch to the selected workspace |
| `Ctrl + D` | Delete the selected workspace (re-opens switcher) |
| `Ctrl + N` | Create a new workspace by name |
| `Ctrl + P` | Create a new workspace at a path |
| `Ctrl + R` | Rename the selected workspace |
| `Escape` | Cancel |

A keybinding legend is shown in the right status bar while the switcher is open.

**Note:** Workspace cycling (`CTRL+]` and `CTRL+[`) always uses case-insensitive alphabetical ordering for predictable, stable navigation. The switcher uses recency-based sorting by default, configurable via `workspace_switcher_sort`.

## Custom Keybindings

If you prefer to set up your own keybindings instead of using `apply_to_config()`:

```lua
local workspace_manager = wezterm.plugin.require("https://github.com/ryanmsnyder/workspace-manager.wezterm")

config.keys = {
  {
    key = "w",
    mods = "CTRL|SHIFT",
    action = workspace_manager.workspace_switcher(),
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

**Note:** Even with custom keybindings, you still need to call `apply_to_config(config)` to register the `workspace_switcher_actions` key table (which powers the in-switcher Ctrl+D/N/P/R bindings) and the event handlers for session persistence and status bar updates.

## API

### Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `wezterm_path` | string | Auto-detected | Path to wezterm executable (only needed if auto-detection fails) |
| `zoxide_path` | string | `"zoxide"` | Path to zoxide binary |
| `show_current_workspace_in_switcher` | boolean | `false` | Show current workspace in the switcher list |
| `show_current_workspace_hint` | boolean | `true` | Show current workspace name in the switcher description bar |
| `start_in_fuzzy_mode` | boolean | `true` | Start switcher in fuzzy search mode (false for positional shortcuts) |
| `notifications_enabled` | boolean | `false` | Enable toast notifications (requires code-signed wezterm on macOS) |
| `workspace_count_format` | string | `"compact"` | Display workspace counts: `nil` (disabled), `"compact"` (2w 3t 5p), or `"full"` (2 wins, 3 tabs, 5 panes) |
| `use_basename_for_workspace_names` | boolean | `false` | Use directory basename instead of full path (falls back for duplicates) |
| `workspace_switcher_sort` | string | `"recency"` | Sort order: `"recency"` (most recent first) or `"alphabetical"` |
| `switcher_legend_enabled` | boolean | `true` | Show keybinding legend in right status bar while switcher is open (see [Status Bar Legend](#status-bar-legend)) |
| `switcher_legend` | table | `nil` | Override right status bar content as a FormatItem list (see [Status Bar Legend](#status-bar-legend)) |
| `colors` | table | `nil` | Override theme colors (see [Styling](#styling)) |

**Session persistence options** (requires `session_enabled = true`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `session_enabled` | boolean | `false` | Enable automatic workspace state save/restore |
| `session_periodic_save_interval` | number | `600` | Seconds between periodic saves (`nil` to disable) |
| `session_periodic_save_all` | boolean | `false` | Periodic save: `true` = all workspaces, `false` = active workspace only |
| `session_max_scrollback_lines` | number | `3500` | Max scrollback lines to capture per pane |
| `session_exclude_workspaces` | table | `{"default"}` | Workspace names to never save or restore |
| `session_state_dir` | string | `nil` | Override state directory (default: `~/.local/share/wezterm/workspace_state/`) |
| `session_on_pane_restore` | function | `nil` | Custom per-pane restore callback (default: replays processes / injects scrollback) |
| `session_restore_on_startup` | boolean | `false` | Automatically restore the most recently used workspace when WezTerm starts |

### Actions

All actions return a WezTerm action that can be used in keybindings:

- `workspace_manager.workspace_switcher()` — Opens the unified switcher (switch, delete, new, rename all from within)
- `workspace_manager.switch_to_previous_workspace()` — Switches to the previously active workspace (Alt-Tab toggle behavior)
- `workspace_manager.next_workspace()` — Cycles to the next workspace in alphabetical order (with wrapping)
- `workspace_manager.previous_workspace()` — Cycles to the previous workspace in alphabetical order (with wrapping)

### `apply_to_config(config)`

Registers event handlers, the `workspace_switcher_actions` key table, and default keybindings.

## Features

### Workspace Switcher

The unified switcher (`LEADER + s`) shows:

1. **Active workspaces** (sorted by recency or alphabetically, marked with 󱂬 icon)
2. **Saved workspaces** from previous sessions (also marked with 󱂬 icon — requires `session_enabled = true`)
3. **Zoxide directory history** (marked with  icon)

While the switcher is open, additional actions are available via key bindings:

- **`Ctrl+D`** — Delete the highlighted workspace. Blocked if you highlight the current workspace. Re-opens the switcher automatically after deleting.
- **`Ctrl+N`** — Create a new named workspace. Input is a name; the new workspace opens at the default cwd.
- **`Ctrl+P`** — Create a new workspace rooted at a path. Input is a filesystem path; the workspace name is derived from the directory basename. Also adds the path to zoxide history.
- **`Ctrl+R`** — Rename the highlighted workspace. If the new name matches an existing workspace, windows are merged into it.

### Status Bar Legend

While the switcher is open, a keybinding legend is shown in the right status bar:

```
^D=del  ^N=new  ^P=path  ^R=rename  Esc=cancel
```

To customize the legend content and styling, set `switcher_legend` to a FormatItem list:

```lua
workspace_manager.switcher_legend = {
  { Foreground = { Color = "#585b70" } },
  { Text = "  ^D=del  ^N=new  ^P=path  ^R=rename  Esc=cancel " },
}
```

If you have your own `update-right-status` handler, disable the built-in legend and emit the event yourself:

```lua
workspace_manager.switcher_legend_enabled = false

wezterm.on("update-right-status", function(window, pane)
  if window:active_key_table() == "workspace_switcher_actions" then
    wezterm.emit("workspace_manager.switcher.update_right_status", window, pane)
    return
  end
  -- your normal right status logic here
end)
```

### Styling

Override any subset of the theme colors via `M.colors`. Values accept a color string (WezTerm AnsiColor name or `"#hex"`) or a list of FormatItems (e.g. `{ { Attribute = { Intensity = "Half" } } }`).

**General colors:**

| Key | Default | Used for |
|-----|---------|----------|
| `highlight` | `"Lime"` | Current workspace label fallback, prompt accents |
| `muted` | `"#888888"` | Legend text, secondary separators |
| `prompt_heading` | `"Bold"` | Heading style for prompts (`"Bold"`, `"Half"`, `"Normal"`, or `nil`) |

**Switcher label segments** (each part of a workspace/zoxide entry can be styled independently):

| Key | Default | Used for |
|-----|---------|----------|
| `switcher_icon` | `nil` | Icon glyph (`󱂬` or ``) — terminal default; current entry falls back to `highlight` |
| `switcher_name` | `nil` | Workspace or directory name — terminal default; current entry falls back to `highlight` |
| `switcher_counts` | `nil` | Count suffix, e.g. `(2w 3t 5p)` — terminal default; current entry falls back to `highlight` |
| `switcher_current` | `nil` | ` (current)` marker — falls back to `highlight` |

```lua
-- Match a Dracula theme
workspace_manager.colors = {
  highlight = "#50fa7b",
  muted = "#6272a4",
}

-- Dim counts with Half intensity (avoids InputSelector selection highlight clash)
workspace_manager.colors = {
  switcher_counts = { { Attribute = { Intensity = "Half" } } },
}

-- Full custom label palette
workspace_manager.colors = {
  switcher_icon    = nil,                                        -- inherit terminal default
  switcher_name    = "#f8f8f2",
  switcher_counts  = { { Attribute = { Intensity = "Half" } } },
  switcher_current = "#50fa7b",
}
```

### Recency Persistence

Workspace access times are saved to `~/.local/share/wezterm/workspace_history.json` and persist across restarts.

### Path Normalization

All workspace names are normalized to use `~` for the home directory. This prevents duplicates when switching between `~/projects` and `/Users/you/projects`.

## Session Persistence

workspace-manager includes built-in session persistence — workspace layouts (panes, tabs, splits, working directories, scrollback) are automatically saved and restored across WezTerm restarts. No external plugins required.

### Quick Setup

```lua
local workspace_manager = wezterm.plugin.require("https://github.com/ryanmsnyder/workspace-manager.wezterm")

workspace_manager.session_enabled = true  -- enable session persistence
workspace_manager.session_restore_on_startup = true  -- optional: restore last workspace on launch

workspace_manager.apply_to_config(config)
```

That's it. With `session_enabled = true`:

- **State is saved automatically** when you switch away from a workspace
- **Previously-active workspaces appear in the switcher** after restarting WezTerm, sorted by recency/alphabetical alongside live ones
- **State is restored** when you select a saved workspace (tabs, pane splits, working directories, scrollback text)
- **Periodic auto-save** runs every 10 minutes as a crash safety net
- **Deleting a workspace** removes its saved state so it won't reappear

With `session_restore_on_startup = true`, WezTerm also opens directly into your most recently used workspace on launch instead of the default workspace.

### State Location

State files are stored at `~/.local/share/wezterm/workspace_state/<workspace-name>.json`.

### How It Works

- **Save on switch**: Before switching away from a workspace, its full layout is captured — all windows, tabs, pane splits, working directories, and scrollback text — and written to disk
- **Lazy restore**: After a restart, saved workspace names are read from the state directory and shown in the switcher alongside live workspaces. The full layout is only restored when you actually select a workspace (fast startup)
- **Startup restore**: With `session_restore_on_startup = true`, the most recently used workspace (by access time) is automatically restored when WezTerm starts. If no saved state exists, WezTerm opens normally
- **In-memory workspaces**: Switching between workspaces that are already running is instant — no restoration needed, they're already in memory
- **Default workspace excluded**: The `"default"` workspace is never saved or restored by default

### Events Reference

The plugin emits events you can hook into for custom behavior:

| Event | When | Parameters | Purpose |
|-------|------|-----------|---------|
| `workspace_manager.workspace_switcher.switching` | **Before** workspace switch | `mux_window, pane, old_workspace, new_workspace` | Fires before every switch (built-in save happens here) |
| `workspace_manager.workspace_switcher.created` | **After** creating new workspace | `mux_window, pane, workspace_name, path` | Fires after a new workspace is created and restored |
| `workspace_manager.workspace_switcher.selected` | **After** switching to existing workspace | `mux_window, pane, workspace_name` | Fires after switching to a live in-memory workspace |
| `workspace_manager.switcher.update_right_status` | While switcher key table is active | `window, pane` | Override to render a custom right status legend |

**Note**: All workspace events pass `MuxWindow` objects as the first parameter (consistent with [smart_workspace_switcher](https://github.com/MLFlexer/smart_workspace_switcher.wezterm) API).

### Using External resurrect.wezterm Plugin Instead

If you prefer to use [MLFlexer/resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm) directly (e.g., to use its fuzzy loader, encryption, or window/tab-level saves), keep `session_enabled = false` and wire up the events manually:

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

Make sure you have zoxide installed and have some directory history. You can also create workspaces manually using `Ctrl+N` from within the switcher.

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
