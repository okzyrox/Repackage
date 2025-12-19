--// Util
--// Author: okzyrox
--/ Date: 2025/12/18

--// Vars
local DebugMode = true

--// Module

local Util = {}
Util.DebugMode = DebugMode

function Util.dprint(...)
	if not DebugMode then
		return
	end
	print(...)
end

function Util.printInstance(instance: Instance, indent: string)
	print(indent .. instance.Name .. " (" .. instance.ClassName .. ")")

	local Children = instance:GetChildren()
	if #Children > 0 then
		for _, child in Children do
			Util.printInstance(child, indent .. "  ")
		end
	end
end

return Util