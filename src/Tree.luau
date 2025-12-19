--// Tree
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

--// Constants
local DB = roblox.getReflectionDatabase()

local EXCLUDED_PROPERTIES = {
	"Parent",
	"ClassName",
	"Name"
}

local SCRIPT_EXTENSIONS = {
	["LocalScript"] = ".client.luau",
	["Script"] = ".server.luau",
	["ModuleScript"] = ".luau",
}

--// Module

local Tree = {}

function Tree.getInstanceProperties(instance: Instance): {[string]: any}
	local properties: {[string]: any} = {}
	local classInfo = DB:GetClass(instance.ClassName)
	if classInfo then
		for _, propInfo in classInfo.Properties do
			if EXCLUDED_PROPERTIES[propInfo.Name] then
				continue
			end
			local success, value = pcall(function()
				return instance[propInfo.Name]
			end)
			if success then
				properties[propInfo.Name] = value
			end
		end
	end
	return properties
end

function Tree.constructInstanceTreeFromInstance(instance: Instance): any
    local children = instance:GetChildren()
    local isScript = SCRIPT_EXTENSIONS[instance.ClassName] ~= nil
    local extension = SCRIPT_EXTENSIONS[instance.ClassName] or ".meta.json"
    
    if #children == 0 then
        if isScript then
            return {
                type = "file",
                name = instance.Name .. extension,
                content = (instance :: any).Source
            }
        elseif instance.ClassName == "Folder" then
            return {
                type = "directory",
                name = instance.Name,
                children = {}
            }
        else
            return {
                type = "file",
                name = instance.Name .. ".meta.json",
                content = serde.encode("json", {
                    -- Name = instance.Name,
                    className = instance.ClassName,
                    properties = Tree.getInstanceProperties(instance)
                })
            }
        end
    else
        local dirChildren = {}
        
        if isScript then
            table.insert(dirChildren, {
                type = "file",
                name = "init" .. extension,
                content = (instance :: any).Source
            })
        elseif instance.ClassName ~= "Folder" then
            table.insert(dirChildren, {
                type = "file",
                name = "init.meta.json",
                content = serde.encode("json", {
                    -- Name = instance.Name,
                    className = instance.ClassName,
                    properties = Tree.getInstanceProperties(instance)
					
                })
            })
        end

        for _, child in children do
            table.insert(dirChildren, Tree.constructInstanceTreeFromInstance(child))
        end

        return {
            type = "directory",
            name = instance.Name,
            children = dirChildren
        }
    end
end

function Tree.constructInstanceTreeFromDirectory(dirPath: string): any
	if not fs.isDir(dirPath) then
		error("Directory does not exist or is not a directory: " .. dirPath)
	end
	local children = fs.readDir(dirPath)

	local dirChildren = {}

	for _, childName in children do
		local childPath = dirPath .. "/" .. childName
		
		if fs.isDir(childPath) then
			table.insert(dirChildren, Tree.constructInstanceTreeFromDirectory(childPath))
		else
			if childPath:find("package.json") then
				continue
			end
			local content = fs.readFile(childPath)
			if childPath:find(".meta.json") then
				local metaJson = serde.decode("json", content)
				local reMetaJson = serde.encode("json", metaJson) -- rencode to remove pretty formatting (if any)
				table.insert(dirChildren, {
					type = "file",
					name = childName,
					content = reMetaJson
				})
				continue
			else
				table.insert(dirChildren, {
					type = "file",
					name = childName,
					content = content
				})
			end
		end
	end

	local packageAssetId: string? = nil

	if fs.isFile(dirPath .. "/package.json") then
		local packageData = fs.readFile(dirPath .. "/package.json")
		local packageJson = serde.decode("json", packageData)
		packageAssetId = packageJson["packageAssetId"]
	end

	local nameParts = dirPath:split("/")
	local lastPart = nameParts[#nameParts]

	return {
		type = "directory",
		name = lastPart,
		packageAssetId = packageAssetId,
		children = dirChildren
	}
end

function Tree.writeInstanceTreeToFS(tree: any, basePath: string)
	if tree.type == "directory" then
		local dirPath = basePath .. "/" .. tree.name
		fs.writeDir(dirPath)
		
		for _, child in tree.children do
			Tree.writeInstanceTreeToFS(child, dirPath)
		end
	elseif tree.type == "file" then
		local filePath = basePath .. "/" .. tree.name
		fs.writeFile(filePath, tree.content)
	end
end

return Tree