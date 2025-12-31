--!nonstrict
--// Util
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local colored = require("./Lib/colored")

--// Vars
local PrintExtraProperties = {
	["Animation"] = {"AnimationId"},
	["Sound"] = {"AudioContent"},
}

--// Module

local Util = {}
Util.DebugMode = false

function Util.dprint(
	...: any
)
	if not Util.DebugMode then
		return
	end
	print(...)
end

function Util.warn(
	...: any
)
	local str = { ... }
	local strFmt = "[WARN] - " .. table.concat(str, " ")
	print(colored(strFmt, "yellow"))
end

function Util.printInstance(
	instance: Instance, 
	indent: string,
	last: boolean?
)
	if last == nil then
		last = true
	end
	
	local prefix = indent
	local connector = last and "└── " or "├── "
	local connectorExtras = last and "    " or "│   "
	
	print(prefix .. connector .. instance.Name .. " (" .. instance.ClassName .. ")")
	
	local extraProps = PrintExtraProperties[instance.ClassName]
	if extraProps then
		for _, propName in extraProps do
			local success, value = pcall(function()
				return instance[propName]
			end)
			if success and value then
				local pPrefix = indent .. (connectorExtras)
				print(pPrefix .. "│ " .. propName .. " = " .. tostring(value))
			end
		end
	end

	local tags = instance:GetTags()
	if #tags > 0 then
		local tPrefix = indent .. (connectorExtras)
		print(tPrefix .. "│ Tags: " .. table.concat(tags, ", "))
	end

	local attributes = instance:GetAttributes()
	for attrName, attrValue in attributes do
		local aPrefix = indent .. (connectorExtras)
		print(aPrefix .. "│ Attribute: " .. attrName .. " = " .. tostring(attrValue))
	end

	local Children = instance:GetChildren()
	if #Children > 0 then
		local cPrefix = indent .. (connectorExtras)
		for i, child in Children do
			local isLastChild = i == #Children
			Util.printInstance(child, cPrefix, isLastChild)
		end
	end
end

function Util.safeDirName(
	name: string
): string
	local safeName = name:gsub("[<>:\"/\\|%?%*]", "_")
	if safeName ~= name then 
		Util.warn(`{name} was converted to {safeName} due to invalid characters`)
	end
	return safeName
end

function Util.getInstancePath(
	instance: Instance
): string
	local parts: {string} = {}
	local currentInstance: Instance? = instance

	while currentInstance ~= nil do
		table.insert(parts, 1, currentInstance.Name)
		currentInstance = currentInstance.Parent
	end

	return table.concat(parts, "/")
end

function Util.getScriptTypeFromName(
	fileName: string
): string?
	if fileName:find("%.client%.luau$") then
		return "LocalScript"
	elseif fileName:find("%.server%.luau$") then
		return "Script"
	elseif fileName:find("%.luau$") then
		return "ModuleScript"
	else
		return nil
	end
end

function Util.randomInt(
	min: number,
	max: number
): number
	math.randomseed(os.clock())
	local random = math.random()

	return math.floor(random * (max - min + 1)) + min
end

function Util.randomIntOfLength(
	length: number
)
	local min = 10 ^ (length - 1)
	local max = (10 ^ length) - 1
	return Util.randomInt(min, max)
end
function Util.stringCombine(
	parts: {string},
	separator: string
): string
	return table.concat(parts, separator)
end

function Util.stringStartsWith(
	string: string,
	prefix: string
): boolean
	return string:sub(1, #prefix) == prefix
end

function Util.stringIsAlphanumeric(
	string: string
): boolean
	if string:match("^%w+$") then
		return true
	else
		return false
	end
end

function Util.stringChars(
	string: string
): {string}
	local chars: {string} = {}
	for i = 1, #string do
		table.insert(chars, string:sub(i, i))
	end
	return chars
end

function Util.matchesFilter(
	strings: {string},
	filterFunc: (string: string) -> boolean
): boolean
	local matching = true
	for _, str in strings do
		if not filterFunc(str) then
			return false
		else
			matching = true
		end
	end
	if matching then
		return true
	end
	return false
end

function Util.stringEndsWith(
	string: string,
	suffix: string
): boolean
	return string:sub(-#suffix) == suffix
end

function Util.joinPathParts(
	...: string
): string
	local parts = { ... }
	local result = ""

	for i, part in parts do
		if type(part) == "string" and part ~= "" then
			part = part:match("^%s*(.-)%s*$") or part
			if i > 1 then
				part = part:gsub("^/+", "")
			end
			part = part:gsub("/+$", "")

			if result == "" then
				result = part
			else
				result = result .. "/" .. part
			end
		end
	end

	return result
end

function Util.tableCount(
	table: { [any]: any }
): number
	local count = 0
	for _key, item in table do
		count += 1
		if type(item) == "table" then
			count += Util.tableCount(item)
		elseif type(item) == "userdata" and typeof(item) == "Instance" then
			count += Util.tableCount(item:GetChildren())
		end
	end
	return count
end

return Util