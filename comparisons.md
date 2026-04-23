# Comparisons

## vs smart_workspace_switcher.wezterm

[smart_workspace_switcher.wezterm](https://github.com/MLFlexer/smart_workspace_switcher.wezterm) is a great plugin and a direct inspiration for workspace-manager. It focuses on fast fuzzy-find switching using zoxide. Here is how the two differ:

| | smart_workspace_switcher | workspace-manager |
|---|---|---|
| **Switcher entries** | Live workspaces + zoxide directories | Live workspaces + saved sessions + zoxide/custom suggestions |
| **Custom entries** | Override `get_choices` with raw `{id, label}` pairs | Override `get_choices` with paths or tables; plugin handles normalization, deduplication, and styling |
| **In-overlay actions** | Switch only | Switch, delete, rename, create by name, create at path |
| **Session persistence** | None (pair with resurrect.wezterm) | Built in and opt-in |
| **Sorting** | Workspaces in mux order, zoxide results in frecency order | All entries sorted by recency (access times tracked on disk) |
| **Zoxide** | Required dependency | Optional (default provider, can disable or replace) |
| **Theming** | Single `workspace_formatter` function | Per-segment color control (icon, name, counts, current marker) |

smart_workspace_switcher is a solid lightweight choice if all you need is a fast workspace picker with zoxide. workspace-manager is designed for people who want lifecycle management and session persistence in the same place.

---

## vs resurrect.wezterm

workspace-manager's session persistence is built on code vendored from [resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm) (MIT licensed). The two plugins have overlapping goals but different scopes.

**What resurrect offers that workspace-manager does not:**

- Encryption of state files (age, rage, GnuPG)
- Window-level and tab-level saves (not just workspace-level)
- A separate fuzzy loader UI for browsing all saved states with date stamps and type-specific formatting
- Remote domain re-attachment (SSH, SSHMUX, WSL, Docker)

**What workspace-manager offers that resurrect does not:**

- Saved workspaces appear in the switcher automatically alongside live ones — no separate UI or keybinding needed
- State is saved automatically on workspace switch, no event wiring required
- Startup restore waits for window geometry to stabilize before restoring pane splits, which avoids the resize issues commonly reported with resurrect
- Deleting a workspace via the switcher also removes its state file so it does not reappear
- Renaming a workspace also renames its state file on disk
- One boolean (`session_enabled = true`) to opt in, vs. multiple keybindings, event handlers, and callbacks

resurrect is a flexible toolkit with granular building blocks. workspace-manager is opinionated and integrated, trading some of that flexibility for a workflow where switching and persistence work together out of the box. If you need encryption, window or tab-level saves, or remote domain support, resurrect is the better fit.

The two can also interoperate — see below.

---

## Using resurrect.wezterm instead

If you prefer to use resurrect.wezterm directly (for encryption, its fuzzy loader, window/tab-level saves, or remote domain support), keep `session_enabled = false` and wire up the events manually:

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
