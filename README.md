# workspace-manager.wezterm

A Wezterm plugin providing an enhanced workspace switcher with:

- **Recency-based ordering** - Recently used workspaces appear first
- **Arbitrary path switching** - Create workspaces at any path (not limited to zoxide history)
- **Workspace closing** - Remove unwanted workspaces
- **Workspace renaming** - Organize with better names

## Installation

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Load the plugin
local workspace_manager = wezterm.plugin.require("https://github.com/yourusername/workspace-manager.wezterm")

-- Required: Path to wezterm executable (needed for CLI commands, since Lua doesn't have shell PATH)
workspace_manager.wezterm_path = "/Applications/WezTerm.app/Contents/MacOS/wezterm"

-- Optional: Configure zoxide path (defaults to "zoxide")
workspace_manager.zoxide_path = "zoxide"

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
| `LEADER + Shift-S` | Previous workspace | Switch to the previously active workspace |

## Custom Keybindings

If you prefer to set up your own keybindings instead of using `apply_to_config()`:

```lua
local workspace_manager = wezterm.plugin.require("https://github.com/yourusername/workspace-manager.wezterm")

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
}
```

## API

### Configuration

- `workspace_manager.wezterm_path` - **Required.** Path to the wezterm executable (e.g., `"/Applications/WezTerm.app/Contents/MacOS/wezterm"` on macOS)
- `workspace_manager.zoxide_path` - Path to the zoxide binary (default: `"zoxide"`)
- `workspace_manager.show_current_workspace_in_switcher` - Show current workspace in the switcher list (default: `true`)
- `workspace_manager.show_current_workspace_hint` - Show current workspace name in the switcher description (default: `false`)
- `workspace_manager.start_in_fuzzy_mode` - Start switcher in fuzzy search mode; set `false` to use positional shortcuts like `1`, `2`, `3` (default: `true`)
- `workspace_manager.notifications_enabled` - Enable toast notifications for workspace actions (default: `false`)
- `workspace_manager.workspace_count_format` - Display workspace counts in switcher and close menus; options: `nil` (disabled), `"compact"` (2w 3t 5p), or `"full"` (2 wins, 3 tabs, 5 panes) (default: `nil`)
- `workspace_manager.use_basename_for_workspace_names` - Use directory basename as workspace name instead of full path (e.g., `myapp` instead of `~/projects/myapp`); automatically falls back to full path for duplicate basenames (default: `false`)

### Actions

All actions return a Wezterm action that can be used in keybindings:

- `workspace_manager.switch_workspace()` - Opens the main workspace switcher UI
- `workspace_manager.new_workspace()` - Prompts for a name to create a new workspace
- `workspace_manager.new_workspace_at_path()` - Prompts for a path to create a workspace rooted there
- `workspace_manager.close_workspace()` - Opens a selector to close a workspace
- `workspace_manager.rename_workspace()` - Prompts for a new name for the current workspace
- `workspace_manager.switch_to_previous_workspace()` - Switches to the previously active workspace

### `apply_to_config(config)`

Adds the default keybindings and event handlers to your config.

## Features

### Workspace Switcher

The main switcher (`LEADER + s`) shows:

1. **Active workspaces** (sorted by recency, marked with 󱂬 icon)
2. **Zoxide directory history** (marked with  icon)

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

## Troubleshooting

### Wezterm CLI not found

The plugin uses `wezterm cli` commands to reliably close workspaces. Since wezterm's Lua environment doesn't have access to your shell's PATH, you must provide the full path to the wezterm executable. Common paths:

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

Zoxide integration inspired by [MLFlexer/smart_workspace_switcher.wezterm](https://github.com/MLFlexer/smart_workspace_switcher.wezterm).

## License

MIT
