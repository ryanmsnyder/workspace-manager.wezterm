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
- [zoxide](https://github.com/ajeetdsouza/zoxide) (optional — used by default for directory history; can be replaced with a custom provider via `get_choices`)
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
| `zoxide_path` | string | `"zoxide"` | Path to zoxide binary (unused when `get_choices` is set) |
| `get_choices` | function/false | `nil` | Custom entry provider function (see [Custom Choices](#custom-choices)). Set to `false` to disable extra entries entirely. |
| `filter_choices` | table/function | `nil` | Filter switcher entries (see [Filtering Choices](#filtering-choices)). Table: exact path allowlist. Function: predicate receiving a choice object, return `true` to keep. |
| `show_current_workspace_in_switcher` | boolean | `false` | Show current workspace in the switcher list |
| `show_current_workspace_hint` | boolean | `true` | Show current workspace name in the switcher description bar |
| `start_in_fuzzy_mode` | boolean | `true` | Start switcher in fuzzy search mode (false for positional shortcuts) |
| `notifications_enabled` | boolean | `false` | Enable toast notifications (requires code-signed wezterm on macOS) |
| `workspace_count_format` | string | `"compact"` | Display workspace counts: `nil` (disabled), `"compact"` (2w 3t 5p), or `"full"` (2 wins, 3 tabs, 5 panes) |
| `use_basename_for_workspace_names` | boolean | `false` | Use directory basename instead of full path (falls back for duplicates) |
| `workspace_switcher_sort` | string | `"recency"` | Sort order: `"recency"` (most recent first) or `"alphabetical"` |
| `switcher_keys` | table | `nil` | Override in-switcher action key bindings (see [Switcher Keys](#switcher-keys)) |
| `show_switcher_hints` | boolean | `true` | Show action key hints in the switcher description bar (both modes). Set to `false` to hide (use `get_switcher_legend()` instead) |
| `workspace_icon` | string | `"󱂬  "` | Icon glyph for workspace entries in the switcher |
| `workspace_icon_current` | string | `nil` | Icon glyph for the active workspace (falls back to `workspace_icon`) |
| `entry_icon` | string | `"  "` | Icon glyph for custom/zoxide entries in the switcher |
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

### Helpers

- `workspace_manager.get_switcher_legend()` — Returns a formatted string of action key hints for use in `set_right_status()` (see [Status Bar Legend](#status-bar-legend))

### `apply_to_config(config)`

Registers event handlers, the `workspace_switcher_actions` key table, and default keybindings.

## Features

### Workspace Switcher

The unified switcher (`LEADER + s`) shows:

1. **Active workspaces** (sorted by recency or alphabetically, marked with 󱂬 icon)
2. **Saved workspaces** from previous sessions (also marked with 󱂬 icon — requires `session_enabled = true`)
3. **Zoxide directory history** or **custom entries** from `get_choices` (marked with  icon)

While the switcher is open, additional actions are available via key bindings:

- **`Ctrl+D`** — Delete the highlighted workspace. Blocked if you highlight the current workspace. Re-opens the switcher automatically after deleting.
- **`Ctrl+N`** — Create a new named workspace. Input is a name; the new workspace opens at the default cwd.
- **`Ctrl+P`** — Create a new workspace rooted at a path. Input is a filesystem path; the workspace name is derived from the directory basename.
- **`Ctrl+R`** — Rename the highlighted workspace. If the new name matches an existing workspace, windows are merged into it.

### Switcher Keys

By default the in-switcher action keys are `Ctrl+D` (delete), `Ctrl+N` (new), `Ctrl+P` (new at path), and `Ctrl+R` (rename). Override them via `switcher_keys`:

```lua
workspace_manager.switcher_keys = {
  delete      = { key = "x", mods = "CTRL" },  -- remap delete to Ctrl+X
  rename      = false,                           -- disable rename entirely
  -- unspecified actions keep their defaults
}
```

Actions: `"delete"`, `"new"`, `"new_at_path"`, `"rename"`. Enter (select) and Escape (cancel) are not configurable.

The description bar and `get_switcher_legend()` both auto-reflect whatever keys are configured. To hide hints from the description bar and show them only in the right-status legend instead:

```lua
workspace_manager.show_switcher_hints = false
```

### Status Bar Legend

The plugin does not register `update-right-status`. Instead, call `workspace_manager.get_switcher_legend()` from your own handler to render the legend while the switcher is open. The legend text automatically reflects the configured `switcher_keys`:

```lua
wezterm.on("update-right-status", function(window, pane)
  if window:active_key_table() == "workspace_switcher_actions" then
    window:set_right_status(workspace_manager.get_switcher_legend())
    return
  end
  -- your normal right status logic here
end)
```

`get_switcher_legend()` returns a formatted string (e.g. `^D=del  ^N=new  ^P=path  ^R=rename  Esc=cancel`) in the muted color. To render your own legend content, format and set it directly:

```lua
wezterm.on("update-right-status", function(window, pane)
  if window:active_key_table() == "workspace_switcher_actions" then
    window:set_right_status(wezterm.format({
      { Foreground = { Color = "#585b70" } },
      { Text = "  ^D=del  ^N=new  ^P=path  ^R=rename  Esc=cancel " },
    }))
    return
  end
  -- your normal right status logic here
end)
```

### Styling

Override any subset of the theme colors via `M.colors`. All keys accept the same format:
- A **color string** (WezTerm AnsiColor name or `"#hex"`) — applied as a foreground color
- A **FormatItem list** — full control over foreground, background, intensity, etc.

```lua
-- Color string (foreground only)
workspace_name = "#cdd6f4"

-- FormatItem list (full control)
workspace_name = {
  { Foreground = { Color = "#cdd6f4" } },
  { Attribute = { Intensity = "Bold" } },
}
```

**Prompt colors:**

| Key | Default | Used for |
|-----|---------|----------|
| `prompt_accent` | `"Lime"` | Workspace name/path text in prompt descriptions, e.g. the `~/ws` in the switcher description and `"Renaming: ~/ws"` |
| `prompt_heading` | Bold | Label text surrounding the accent, e.g. `"Renaming:"`, `"Directory does not exist:"` |
| `muted` | `"#888888"` | Secondary text: switcher legend and keyboard shortcut hints in description bars |

**Switcher label segments** (each segment of a label can be styled independently per entry category):

The switcher has three entry categories: workspace entries (non-active), the current active workspace, and custom/zoxide entries (not yet workspaces). Each category's segments can be colored independently.

*Non-active workspace entries:*

| Key | Default | Used for |
|-----|---------|----------|
| `workspace_icon` | `nil` | Icon glyph — terminal default |
| `workspace_name` | `nil` | Workspace name — terminal default |
| `workspace_counts` | `nil` | Count suffix, e.g. `(2w 3t 5p)` — terminal default |

*Active (current) workspace — each falls back to the matching `workspace_*` key:*

| Key | Default | Used for |
|-----|---------|----------|
| `workspace_icon_current` | `nil` | Icon glyph |
| `workspace_name_current` | `nil` | Workspace name |
| `workspace_counts_current` | `nil` | Count suffix |
| `workspace_current_marker` | `nil` | ` (current)` text appended to the label — falls back to `prompt_accent` |

*Custom/zoxide entries — each falls back to the matching `workspace_*` key:*

| Key | Default | Used for |
|-----|---------|----------|
| `entry_icon` | `nil` | Icon glyph |
| `entry_name` | `nil` | Entry name |

```lua
-- Match a Dracula theme
workspace_manager.colors = {
  prompt_accent = "#50fa7b",
  muted = "#6272a4",
}

-- Dim counts with Half intensity (avoids InputSelector selection highlight clash)
workspace_manager.colors = {
  workspace_counts = { { Attribute = { Intensity = "Half" } } },
}

-- Full custom label palette with per-category styling
workspace_manager.colors = {
  prompt_accent            = "#50fa7b",
  workspace_name           = "#f8f8f2",                              -- non-active workspace names
  workspace_counts         = { { Attribute = { Intensity = "Half" } } },
  workspace_name_current   = "#50fa7b",                              -- active workspace name
  workspace_current_marker = "#50fa7b",                              -- "(current)" marker
  entry_name               = "#6272a4",                              -- custom/zoxide entry names
}
```

### Non-fuzzy mode: shortcut label column colors

When `start_in_fuzzy_mode = false`, each row shows a shortcut key (e.g. `1.`, `2.`). WezTerm lets you color that column via two entries in `config.colors` (nightly builds only):

```lua
config.colors = {
  input_selector_label_bg = { Color = "#1e1e2e" },
  input_selector_label_fg = { Color = "#585b70" },
}
```

This is a WezTerm-level setting, not a plugin setting — set it directly in your `config.colors` table. There is no equivalent for the selected row highlight color, which uses reverse-video and is not configurable.

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

**Switcher lifecycle** (pass `GuiWindow`):

| Event | When | Parameters |
|-------|------|-----------|
| `workspace_manager.switcher.opened` | Switcher overlay appears | `window, pane` |
| `workspace_manager.switcher.canceled` | Dismissed without action (Escape / click-outside) | `window, pane` |

**Workspace transitions** (pass `MuxWindow`):

| Event | When | Parameters |
|-------|------|-----------|
| `workspace_manager.workspace_switcher.switching` | **Before** any workspace switch | `mux_window, pane, old_workspace, new_workspace` |
| `workspace_manager.workspace_switcher.created` | **After** creating a new workspace | `mux_window, pane, workspace_name[, path]` |
| `workspace_manager.workspace_switcher.selected` | **After** switching to an existing workspace | `mux_window, pane, workspace_name` |

**Workspace management** (pass `GuiWindow`):

| Event | When | Parameters |
|-------|------|-----------|
| `workspace_manager.workspace_switcher.deleted` | After a workspace is deleted | `window, pane, workspace_name` |
| `workspace_manager.workspace_switcher.renamed` | After a workspace is renamed or merged | `window, pane, old_name, new_name` |

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

-- Restore workspace state when creating a new workspace from the switcher
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

Make sure you have zoxide installed and have some directory history. You can also create workspaces manually using `Ctrl+N` from within the switcher, or provide your own entry list via `get_choices` (see [Custom Choices](#custom-choices)).

### Icons not displaying

The plugin uses Nerd Font icons. Make sure your terminal font includes Nerd Font symbols.

### Notifications not working

Toast notifications are disabled by default. To enable them:

```lua
workspace_manager.notifications_enabled = true
```

**Note:** On macOS, toast notifications require a code-signed application. If you're running WezTerm built from source, installed via Nix, or using a non-signed build, notifications will not work. Use the official signed release from [WezTerm releases](https://github.com/wez/wezterm/releases) if you want notifications.

## Custom Choices

By default, the switcher shows directories from [zoxide](https://github.com/ajeetdsouza/zoxide) history below the workspace list. You can replace this with your own function using `get_choices`.

### Field reference

Each entry returned by `get_choices` can be a **path string** or a **table**:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes (table only) | The WezTerm workspace name — used when creating/switching to the workspace, and shown in the switcher unless `label` is set |
| `path` | No | Working directory for the new workspace pane. Defaults to `~` when omitted. Supports `~` prefix. |
| `label` | No | Display name shown in the switcher instead of `name`. Useful for shorter or friendlier names. |

A plain **path string** (e.g. `"~/Code/my-project"`) is treated as both the path and the source for the workspace name (derived from the path).

### How it works

- **Deduplication**: Entries whose name matches an already-active or saved workspace are automatically excluded, so the same workspace doesn't appear twice.
- **Normalization**: Absolute home paths are shown with a `~` prefix (e.g. `/Users/ryan/Code/foo` displays as `~/Code/foo`). The `~` prefix is also accepted in `path` values and expanded automatically.
- **Workspace creation**: Selecting an entry creates a new WezTerm workspace. If `path` is set, the initial pane opens in that directory; otherwise it opens in `~`.
- **Label persistence**: If an entry has a `label`, it is shown in the switcher both before and after the workspace becomes live — the label is preserved as a display override for the workspace name.

### Examples

```lua
-- Simplest: a list of paths. Workspace name derived from each path.
workspace_manager.get_choices = function()
  return {
    "~/Code/project-alpha",
    "~/Code/project-beta",
    "/opt/work/service-one",
  }
end

-- Named workspaces without a specific directory (cwd defaults to ~)
workspace_manager.get_choices = function()
  return {
    { name = "api" },
    { name = "frontend" },
  }
end

-- Named workspaces with a specific directory
workspace_manager.get_choices = function()
  return {
    { name = "api",      path = "~/Code/api-server" },
    { name = "frontend", path = "~/Code/web-app" },
  }
end

-- Custom display labels (name is the workspace name, label is what's shown in the switcher)
workspace_manager.get_choices = function()
  return {
    { name = "my-corp-monorepo", label = "Monorepo" },
    { name = "api-server",       label = "API", path = "~/Code/api-server" },
  }
end
```

To disable extra entries entirely (show only live and saved workspaces):

```lua
workspace_manager.get_choices = false
```

## Filtering Choices

Use `filter_choices` to control which **suggested entries** appear in the switcher. It accepts a **table** (path allowlist) or a **function** (predicate).

> **Note:** `filter_choices` only affects custom/zoxide suggestions. Workspaces you've created — whether currently running or saved from a previous session — always appear in the switcher regardless of the filter.

### Table allowlist

The simplest form — a list of exact path strings. Only custom/zoxide entries whose `normalized` path exactly matches one of the listed paths are kept.

```lua
workspace_manager.filter_choices = {
  "~/Code/project-alpha",
  "~/Code/project-beta",
}
```

### Predicate function

For more control, provide a function that receives a choice object and returns `true` to keep it. Use this for subdirectory matching, metadata-based filtering, or anything beyond exact paths.

**Available fields:**

| Field | Workspace entries | Custom/zoxide entries | Description |
|-------|:-----------------:|:---------------------:|-------------|
| `id` | yes | yes | Workspace name or path identifier |
| `label` | yes | yes | Display name (before switcher formatting) |
| `normalized` | yes | yes | Path-normalized name (`~`-prefixed) |
| `is_workspace` | `true` | `false` | Whether this is a live or saved workspace |
| `is_saved` | yes | — | Disk-only (not a running workspace) |
| `access_time` | yes | — | Last access timestamp (0 if never accessed) |
| `name` | — | yes | Explicit workspace name from the provider |
| `path` | — | yes | Working directory path |
| `has_path` | — | yes | Whether `path` was explicitly set |

```lua
-- Only show zoxide suggestions under ~/Code (including subdirectories)
workspace_manager.filter_choices = function(choice)
  if choice.is_workspace then return true end  -- workspaces always shown; filter targets suggestions only
  return choice.normalized:find("^~/Code/") ~= nil
end

-- Auto-clean: hide saved workspaces not accessed in the last 30 days
workspace_manager.filter_choices = function(choice)
  if choice.is_saved and choice.access_time < os.time() - 30 * 86400 then
    return false
  end
  return true
end

-- Exclude entries matching a name pattern (e.g. scratch or temp workspaces)
workspace_manager.filter_choices = function(choice)
  return not choice.normalized:find("scratch") and not choice.normalized:find("tmp")
end

-- Combine: always show live workspaces, prune saved ones older than 14 days, limit zoxide to ~/Code
workspace_manager.filter_choices = function(choice)
  if choice.is_workspace and not choice.is_saved then return true end
  if choice.is_saved then return choice.access_time > os.time() - 14 * 86400 end
  return choice.normalized:find("^~/Code/") ~= nil
end
```

## Acknowledgments

- Zoxide integration inspired by [MLFlexer/smart_workspace_switcher.wezterm](https://github.com/MLFlexer/smart_workspace_switcher.wezterm)
- Session persistence powered by code from [MLFlexer/resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm) (MIT licensed)

## License

MIT
