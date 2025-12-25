--!nonstrict
--// Util
--// Author: okzyrox
--/ Date: 2025/12/18

--// Vars
local PrintExtraProperties = {
	["Animation"] = {"AnimationId"},
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

function Util.printInstance(
	instance: Instance, 
	indent: string
)
	print(indent .. instance.Name .. " (" .. instance.ClassName .. ")")
	local extraProps = PrintExtraProperties[instance.ClassName]
	if extraProps then
		for _, propName in extraProps do
			local success, value = pcall(function()
				return instance[propName]
			end)
			if success and value then
				print(indent .. "  |" .. propName .. " = " .. tostring(value))
			end
		end
	end

	local Children = instance:GetChildren()
	if #Children > 0 then
		for _, child in Children do
			Util.printInstance(child, indent .. "  ")
		end
	end
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

function Util.joinPathParts(
	...: string
): string
    local parts = { ... }
    local result = ""

    for i, part in parts do
        if type(part) == "string" and part ~= "" then
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