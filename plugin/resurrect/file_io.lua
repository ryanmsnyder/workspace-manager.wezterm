local wezterm = require("wezterm") --[[@as Wezterm]]

local pub = {}

-- Write a file with the content of a string
---@param file_path string full filename
---@return boolean success result
---@return string|nil error
function pub.write_file(file_path, str)
	local suc, err = pcall(function()
		local handle = io.open(file_path, "w+")
		if not handle then
			error("Could not open file: " .. file_path)
		end
		handle:write(str)
		handle:flush()
		handle:close()
	end)
	return suc, err
end

-- Read a file and return its content
---@param file_path string full filename
---@return boolean success result
---@return string|nil error
function pub.read_file(file_path)
	local stdout
	local suc, err = pcall(function()
		local handle = io.open(file_path, "r")
		if not handle then
			error("Could not open file: " .. file_path)
		end
		stdout = handle:read("*a")
		handle:close()
	end)
	if suc then
		return suc, stdout
	else
		return suc, err
	end
end

--- Sanitize the input by replacing control characters and invalid UTF-8 sequences with valid \uxxxx unicode
--- @param data string
--- @return string
local function sanitize_json(data)
	-- escapes control characters to ensure valid json
	data = data:gsub("[\x00-\x1F]", function(c)
		return string.format("\\u00%02X", string.byte(c))
	end)
	return data
end

---@param file_path string
---@param state table
---@param event_type "workspace" | "window" | "tab"
function pub.write_state(file_path, state, event_type)
	local json_state = wezterm.json_encode(state)
	json_state = sanitize_json(json_state)
	local ok, err = pub.write_file(file_path, json_state)
	if not ok then
		wezterm.log_error("Failed to write state: " .. tostring(err))
	end
end

---@param file_path string
---@return table|nil
function pub.load_json(file_path)
	local lines = {}
	local ok, err = pcall(function()
		for line in io.lines(file_path) do
			table.insert(lines, line)
		end
	end)
	if not ok then
		wezterm.log_error("Failed to read state file: " .. tostring(err))
		return nil
	end
	local json = table.concat(lines)
	if not json or json == "" then
		return nil
	end
	json = sanitize_json(json)
	local parsed, parse_err = pcall(function()
		return wezterm.json_parse(json)
	end)
	if not parsed then
		wezterm.log_error("Failed to parse state JSON: " .. tostring(parse_err))
		return nil
	end
	return wezterm.json_parse(json)
end

return pub
