local wezterm = require("wezterm")

local M_ref -- reference to plugin config table (set via setup)

local mod = {}

local DEFAULT_COLORS = {
  highlight = "Lime",
  muted = "#888888",
  prompt_heading = "Bold",
}

function mod.setup(plugin)
  M_ref = plugin
end

function mod.get_color(key)
  if M_ref.colors and M_ref.colors[key] ~= nil then
    return M_ref.colors[key]
  end
  return DEFAULT_COLORS[key]
end

-- Converts a color string (AnsiColor name or "#hex") to a Foreground FormatItem.
function mod.fg(color_string)
  if color_string:sub(1, 1) == "#" then
    return { Foreground = { Color = color_string } }
  else
    return { Foreground = { AnsiColor = color_string } }
  end
end

-- Builds a FormatItem list for prompt headings using the configured intensity.
function mod.build_heading(text)
  local items = {}
  local intensity = mod.get_color("prompt_heading")
  if intensity and intensity ~= "Normal" then
    table.insert(items, { Attribute = { Intensity = intensity } })
  end
  table.insert(items, { Text = text })
  return items
end

-- Resolves a switcher segment color. For current entries, falls back to highlight if the key is nil.
function mod.get_switcher_color(key, is_current)
  local color = mod.get_color(key)
  if color then return color end
  if is_current then return mod.get_color("highlight") end
  return nil
end

-- Appends a styled text segment to a FormatItems list. Skips empty strings.
-- style can be nil (no styling), a color string (treated as foreground), or
-- a list of FormatItems (e.g. { { Attribute = { Intensity = "Half" } } }).
function mod.append_segment(items, text, style)
  if text == "" then return end
  table.insert(items, "ResetAttributes")
  if type(style) == "string" then
    table.insert(items, mod.fg(style))
  elseif type(style) == "table" then
    for _, item in ipairs(style) do
      table.insert(items, item)
    end
  end
  table.insert(items, { Text = text })
end

-- Builds a fully formatted switcher label with independently styled segments.
function mod.build_switcher_label(icon, name, counts, is_current)
  local items = {}
  mod.append_segment(items, icon, mod.get_switcher_color("switcher_icon", is_current))
  mod.append_segment(items, name, mod.get_switcher_color("switcher_name", is_current))
  mod.append_segment(items, counts, mod.get_switcher_color("switcher_counts", is_current))
  if is_current then
    mod.append_segment(items, " (current)", mod.get_switcher_color("switcher_current", is_current))
  end
  table.insert(items, "ResetAttributes")
  return wezterm.format(items)
end

return mod
