# get_choices recipes

A collection of `get_choices` examples for the workspace switcher. Each recipe is self-contained and can be used as-is or combined with others.

See the [Custom Choices](README.md#custom-choices) section of the README for the full field reference.

---

## Directories from a folder + capped zoxide

Scan a project directory for subdirectories, then append the top N entries from your zoxide history. Non-directory entries (files, symlinks, etc.) are filtered out via `pcall(wezterm.read_dir, path)`.

```lua
workspace_manager.get_choices = function()
  local entries = {}

  -- All subdirectories of ~/Code
  local ok, paths = pcall(wezterm.read_dir, wezterm.home_dir .. "/Code")
  if ok and paths then
    for _, path in ipairs(paths) do
      if pcall(wezterm.read_dir, path) then
        table.insert(entries, path)
      end
    end
  end

  -- Top 10 entries from zoxide history
  for _, path in ipairs(workspace_manager.get_zoxide_paths(10)) do
    table.insert(entries, path)
  end

  return entries
end
```

---

## Multiple project directories

Scan several root directories and combine them into a single list.

```lua
workspace_manager.get_choices = function()
  local entries = {}
  local roots = {
    wezterm.home_dir .. "/Code",
    wezterm.home_dir .. "/Work",
  }

  for _, root in ipairs(roots) do
    local ok, paths = pcall(wezterm.read_dir, root)
    if ok and paths then
      for _, path in ipairs(paths) do
        if pcall(wezterm.read_dir, path) then
          table.insert(entries, path)
        end
      end
    end
  end

  return entries
end
```

---

## Static project list + zoxide

Pin a fixed set of projects at the top, then fill in with zoxide history.

```lua
workspace_manager.get_choices = function()
  local pinned = {
    "~/Code/my-app",
    "~/Code/infra",
    "~/Notes",
  }

  local entries = {}
  for _, path in ipairs(pinned) do
    table.insert(entries, path)
  end
  for _, path in ipairs(workspace_manager.get_zoxide_paths(10)) do
    table.insert(entries, path)
  end

  return entries
end
```

---

## Live workspaces only

Only show workspaces currently running in memory — not ones from a previous session waiting to be restored.

```lua
workspace_manager.get_choices = false

workspace_manager.filter_choices = function(choice)
  return not choice.is_saved
end
```

---

## All workspaces, no extra entries

Show both live and saved workspaces (requires `session_enabled = true`) but hide zoxide and custom suggestions.

```lua
workspace_manager.get_choices = false
```

---

## Zoxide only, capped

Replace the default (uncapped) zoxide list with a shorter one.

```lua
workspace_manager.get_choices = function()
  return workspace_manager.get_zoxide_paths(25)
end
```
