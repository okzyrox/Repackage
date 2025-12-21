--[[
* Based off of the termcolor project
* https://pypi.org/project/termcolor/
]]

local ATTRIBUTES = {
	bold = 1,
	dark = 2,
	underline = 4,
	blink = 5,
	reverse = 7,
	concealed = 8,
	strike = 9,
}

local HIGHLIGHTS = {
	on_black = 40,
	on_grey = 40,
	on_red = 41,
	on_green = 42,
	on_yellow = 43,
	on_blue = 44,
	on_magenta = 45,
	on_cyan = 46,
	on_light_grey = 47,
	on_dark_grey = 100,
	on_light_red = 101,
	on_light_green = 102,
	on_light_yellow = 103,
	on_light_blue = 104,
	on_light_magenta = 105,
	on_light_cyan = 106,
	on_white = 107,
}

local COLORS = {
	black = 30,
	grey = 30,
	red = 31,
	green = 32,
	yellow = 33,
	blue = 34,
	magenta = 35,
	cyan = 36,
	light_grey = 37,
	dark_grey = 90,
	light_red = 91,
	light_green = 92,
	light_yellow = 93,
	light_blue = 94,
	light_magenta = 95,
	light_cyan = 96,
	white = 97,
}

local RESET = "\27[0m"

local function colored(text, color, on_color, attrs)
	local result = tostring(text)
	local fmt = "\27[%dm%s"
	local rgbFore = "\27[38;2;%d;%d;%dm%s"
	local rgbBack = "\27[48;2;%d;%d;%dm%s"

	if color ~= nil then
		if type(color) == "string" then
			result = string.format(fmt, COLORS[color], result)
		elseif type(color) == "table" then
			result = string.format(rgbFore, color[1], color[2], color[3], result)
		end
	end

	if on_color ~= nil then
		if type(on_color) == "string" then
			result = string.format(fmt, HIGHLIGHTS[on_color], result)
		elseif type(on_color) == "table" then
			result = string.format(rgbBack, on_color[1], on_color[2], on_color[3], result)
		end
	end

	if attrs ~= nil then
		for _, attr in ipairs(attrs) do
			result = string.format(fmt, ATTRIBUTES[attr], result)
		end
	end

	return result .. RESET
end

return colored