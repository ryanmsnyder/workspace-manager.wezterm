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
| `LEADER + n` | New workspace | Prompt for a path to create a new workspace |
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

- `workspace_manager.zoxide_path` - Path to the zoxide binary (default: `"zoxide"`)

### Actions

All actions return a Wezterm action that can be used in keybindings:

- `workspace_manager.switch_workspace()` - Opens the main workspace switcher UI
- `workspace_manager.new_workspace()` - Prompts for a path to create a new workspace
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
- Shows a toast notification when closing multiple windows
- Removes the workspace from the recency history

### Workspace Renaming

- Renames the current workspace
- If the new name matches an existing workspace, windows are merged
- Access time is preserved after rename

## Troubleshooting

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

## License

MIT
