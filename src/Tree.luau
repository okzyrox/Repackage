--!nonstrict
--// Tree
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local TreeDataTypes = require("./TreeDataTypes")
local Util = require("./Util")
local Config = require("./Config")

local DMPLib = require("./Lib/diff_match_patch")

--// Types
export type ScriptNode = LocalScript | Script | ModuleScript
export type TreeNodeType = "file" | "directory" | "binaryfile"
export type TreeNode = {
	type: TreeNodeType,
	name: string,
	content: string?, --/ either file source code or meta content
	children: {TreeNode}?,

	--/ only for uppermost meta package:
	packageAssetId: string?, --/ refers to the corresponding asset
	packageRevisionId: string?, --/ refers to the revision id of when the package was last updated
}

export type TreeComparisonResult = {
	added: {{path: string, node: TreeNode}},
	removed: {{path: string, node: TreeNode}},
	modified: {{path: string, node: TreeNode, oldContent: string?}},
	moved: {{oldPath: string, newPath: string, node: TreeNode}},
	anyChanges: boolean
}

export type TreeState = "Unchanged" | "Outdated" | "Modified" | "None"

--// Constants
local DB = roblox.getReflectionDatabase()

local EXCLUDED_PROPERTIES = {
	"Parent",
	"ClassName",
	"Source",
	"Name"
}

local SCRIPT_EXTENSIONS = {
	["LocalScript"] = ".client.luau",
	["Script"] = ".server.luau",
	["ModuleScript"] = ".luau",
}

local PACKAGE_META_FILE = "repackage.json"
local PACKAGE_ROOT_APPEND = ".Package"
local REF_PROPERTY_EXT = {
	Prefix = "Repackage_",
	Suffix = "_RefPath"
}

--// Module

local Tree = {}
Tree.PACKAGE_META_FILE_PATH = PACKAGE_META_FILE
Tree.PACKAGE_ROOT_APPEND = PACKAGE_ROOT_APPEND
Tree.REF_PROPERTY_EXT = REF_PROPERTY_EXT

function Tree.getRefPathAttrName(
	propName: string
): string
	return REF_PROPERTY_EXT.Prefix .. propName .. REF_PROPERTY_EXT.Suffix
end

function Tree.getDataTypePropertyValue(
	value: any
): TreeDataTypes.Deserialisable
	local dataType = typeof(value)
	if TreeDataTypes[dataType] then
		local serialiser = TreeDataTypes[dataType].Ser
		return serialiser(value)
	else
		Util.warn("No serialiser for data type:", dataType)
		return tostring(value)
	end
end

function Tree.getDataTypeFromPropertyValue(
	value: any
): TreeDataTypes.Serialisable
	local dataType = ""
	for typeName, _ in value do
		dataType = typeName
		break
	end

	if TreeDataTypes[dataType] then
		local deserialiser = TreeDataTypes[dataType].Des
		return deserialiser(value)
	else
		Util.warn("No deserialiser for data type:", dataType)
		return tostring(value)
	end
end

function Tree.getAttributePropertyValue(
	value: any
): any?
	local genericType = type(value)

	if genericType == "string" then
		return {
			String = value
		}
	elseif genericType == "number" then
		return {
			Float64 = value
		}
	elseif genericType == "boolean" then
		return {
			Bool = value
		}
	elseif genericType == "userdata" then
		return Tree.getDataTypePropertyValue(value)
	else
		Util.warn("Unknown attribute type:", genericType)
		return nil
	end
end

function Tree.getInstanceProperties(
	instance: Instance
): {[string]: any}
	local properties: {[string]: any} = {}
	local tags: {string} = {}
	local attributes: {[string]: any} = {}
	local classInfo = DB:GetClass(instance.ClassName)
	if classInfo then
		for _, propInfo in classInfo.Properties do
			if table.find(EXCLUDED_PROPERTIES, propInfo.Name) then
				continue
			end
			local success, value = pcall(function()
				return instance[propInfo.Name]
			end)
			if value == classInfo.DefaultProperties[propInfo.Name] then
				continue
			end
			if success then
				if type(value) == "userdata" then
					local dataType = typeof(value)
					if dataType == "EnumItem" then
						properties[propInfo.Name] = value.Name
					else
						if propInfo.Datatype == "Ref" then
							local refPath = Util.getInstancePath(value)
							local refPathAttrName = Tree.getRefPathAttrName(propInfo.Name)
							attributes[refPathAttrName] = {
								String = refPath
							}
						else
							properties[propInfo.Name] = Tree.getDataTypePropertyValue(value)
						end
					end
				else
					properties[propInfo.Name] = value
				end
			end
		end
	end

	for attrName, attrValue in instance:GetAttributes() do
		attributes[attrName] = Tree.getAttributePropertyValue(attrValue)
	end
	
	for _, tag in instance:GetTags() do
		table.insert(tags, tag)
	end

	if next(attributes) ~= nil then
		properties["Attributes"] = attributes
	end

	if #tags > 0 then
		properties["Tags"] = tags
	end

	return properties
end

function Tree.addInstanceProperties(
	instance: Instance,
	properties: {[string]: any}
)
	local class = DB:GetClass(instance.ClassName)
	if not class then
		error("Invalid or unsupported class for instance: " .. instance.ClassName)
	end
	for propName, propValue in properties do
		local propertyInfo = class.Properties[propName]
		if propName == "Attributes" then
			for attrName, attrValue in propValue do
				if not TreeDataTypes.validateAttributeName(attrName) then
					error("Invalid attribute name: " .. attrName)
				end
				for _attrType, attrTrueValue in attrValue do
					instance:SetAttribute(attrName, attrTrueValue)
				end
			end
			continue
		elseif propName == "Tags" then
			for _, tagName in propValue do
				instance:AddTag(tagName)
			end
			continue
		end

		pcall(function()
			if type(propValue) == "table" then
				if propertyInfo.Datatype == "Ref" then
					-- workaround: store as an attribute with a path then resolve later
					local refResolvingPath: string = Tree.getDataTypeFromPropertyValue(propValue) :: string
					local refPathAttrName = Tree.getRefPathAttrName(propName)
					instance:SetAttribute(refPathAttrName, refResolvingPath)
				else
					instance[propName] = Tree.getDataTypeFromPropertyValue(propValue)
				end
			else
				instance[propName] = propValue
			end
		end)
	end
end

function Tree.resolvePropertyRefs(
	instance: Instance,
	root: Instance
)
	local class = DB:GetClass(instance.ClassName)
	if not class then
		error("Invalid or unsupported class for instance: " .. instance.ClassName)
	end

	for propName, propertyInfo in class.Properties do
		if propertyInfo.Datatype == "Ref" then
			local attrs = instance:GetAttributes()
			local refPathAttrName = Tree.getRefPathAttrName(propName)
			local refPath = attrs[refPathAttrName]
			if refPath then
				local refInstance = Util.getInstanceFromPath(root, refPath)
				if refInstance then
					Util.info("Resolved reference for property:", propName, "to instance at path:", refPath)
					instance[propName] = refInstance
				else
					Util.warn("Could not resolve reference for property:", propName, "at path:", refPath)
				end
				instance:SetAttribute(refPathAttrName, nil) -- clean up
			else
				Util.warn("No reference attribute found for property:", propName, refPathAttrName)
			end
		end
	end
end

function Tree.constructInstanceTreeFromInstance(
	instance: Instance | {Instance}, 
	packageName: string?, 
	packageAssetId: string?, 
	packageRevisionId: string?
): TreeNode
	if typeof(instance) == "table" then
		if #instance == 0 then
			error("Instance array is empty")
		end
		return {
			type = "directory",
			name = (packageName or "PackageRoot") .. PACKAGE_ROOT_APPEND,
			packageAssetId = packageAssetId,
			packageRevisionId = packageRevisionId,
			children = (function()
				local children = {}
				for _, inst in instance do
					local treeSuccess, tree = pcall(function()
						return Tree.constructInstanceTreeFromInstance(inst)
					end)
					if treeSuccess then
						table.insert(children, tree)
					else
						Util.warn("Could not construct instance tree for instance:", inst.Name)
						print(tree)
					end
				end
				return children
			end)()
		} :: TreeNode
	end

	local children = instance:GetChildren()
	local tags = instance:GetTags()
	local attributes = instance:GetAttributes()
	local isScript = SCRIPT_EXTENSIONS[instance.ClassName] ~= nil
	local extension = SCRIPT_EXTENSIONS[instance.ClassName] or ".meta.json"

	local hasTags = #tags > 0
	local hasAttributes = next(attributes) ~= nil

	if #children == 0 and not hasTags and not hasAttributes then
		if isScript then
			return {
				type = "file",
				name = instance.Name .. extension,
				content = (instance :: ScriptNode).Source
			}
		elseif instance.ClassName == "Folder" then
			return {
				type = "directory",
				name = instance.Name,
				children = {}
			}
		else
			if Config.get("serialiseNonScripts") ~= true then
				local tracked = {}
				local class = DB:GetClass(instance.ClassName)
				if class then
					for propName, propertyInfo in class.Properties do
						if propertyInfo.Datatype == "Ref" then
							local success, refValue = pcall(function()
								return instance[propName]
							end)
							if success and refValue and typeof(refValue) == "Instance" then
								local refPath = Util.getInstancePath(refValue)
								local refPathAttrName = Tree.getRefPathAttrName(propName)
								instance:SetAttribute(refPathAttrName, refPath)
								tracked[instance] = refPathAttrName
							end
						end
					end
				end
				local instances = {instance}
				local serModel = roblox.serializeModel(instances, true)

				for inst, attrName in tracked do -- cleanup; resolves comp
					inst:SetAttribute(attrName, nil)
				end

				return {
					type = "binaryfile",
					name = instance.Name .. ".meta.rbxmx",
					content = serModel
				}
			else
				return {
					type = "file",
					name = instance.Name .. ".meta.json",
					content = serde.encode("json", {
						["name"] = instance.Name, --/ in the event it has to be renamed due to invalid chars:
						["className"] = instance.ClassName,
						["properties"] = Tree.getInstanceProperties(instance)
					})
				}
			end
		end
	else
		local dirChildren = {}
		
		if isScript then
			table.insert(dirChildren, {
				type = "file",
				name = "init" .. extension,
				content = (instance :: ScriptNode).Source
			})

			if hasTags or hasAttributes then
				table.insert(dirChildren, {
					type = "file",
					name = "init.meta.json",
					content = serde.encode("json", {
						["name"] = instance.Name,
						["properties"] = Tree.getInstanceProperties(instance)
					})
				})
			end
		elseif instance.ClassName ~= "Folder" then
			if Config.get("serialiseNonScripts") ~= true then
				local extracted = {} --/ extract non-binary-files to ser alongside
				for _, child in children do
					if SCRIPT_EXTENSIONS[child.ClassName] or child.ClassName == "Folder" then
						table.insert(extracted, child)
					end
				end

				local tracked = {}
				local class = DB:GetClass(instance.ClassName)
				if class then
					for propName, propertyInfo in class.Properties do
						if propertyInfo.Datatype == "Ref" then
							local success, refValue = pcall(function()
								return instance[propName]
							end)
							if success and refValue and typeof(refValue) == "Instance" then
								local refPath = Util.getInstancePath(refValue)
								local refPathAttrName = Tree.getRefPathAttrName(propName)
								instance:SetAttribute(refPathAttrName, refPath)
								tracked[instance] = refPathAttrName
							end
						end
					end
				end
				for _, descendant in instance:GetDescendants() do
					local descendantIsExtracted = false
					for _, extractedInstance in extracted do
						if descendant == extractedInstance or descendant:IsDescendantOf(extractedInstance) then
							descendantIsExtracted = true
							break
						end
					end
					if descendantIsExtracted then
						continue
					end

					local descClass = DB:GetClass(descendant.ClassName)
					if descClass then
						for propName, propertyInfo in descClass.Properties do
							if propertyInfo.Datatype == "Ref" then
								local success, refValue = pcall(function()
									return descendant[propName]
								end)
								if success and refValue then
									local refPath = Util.getInstancePath(refValue)
									local refPathAttrName = Tree.getRefPathAttrName(propName)
									descendant:SetAttribute(refPathAttrName, refPath)
									tracked[descendant] = refPathAttrName
								end
							end
						end
					end
				end

				for _, extractedInstance in extracted do
					extractedInstance.Parent = nil
				end
				-- essentially we remove them when we serialise to remove dupes
				-- and then those are automatically added back upon deserialisation and reserialisation as well
				local instances = {instance}
				local serModel = roblox.serializeModel(instances, true)

				for _, extractedInstance in extracted do -- re-fix
					extractedInstance.Parent = instance
				end

				for inst, attrName in tracked do -- cleanup; resolves comp
					inst:SetAttribute(attrName, nil)
				end

				table.insert(dirChildren, {
					type = "binaryfile",
					name = "init.meta.rbxmx",
					content = serModel
				})

				for _, extractedInstance in extracted do
					local nodeSuccess, node = pcall(function()
						return Tree.constructInstanceTreeFromInstance(extractedInstance)
					end)
					if nodeSuccess then
						table.insert(dirChildren, node)
					else
						Util.warn("Could not construct tree for extracted instance:", extractedInstance.Name)
						print(node)
					end
				end

				return {
					type = "directory",
					name = instance.Name,
					children = dirChildren
				}
			else
				local success, props = pcall(function()
					return Tree.getInstanceProperties(instance)
				end)

				if not success then
					Util.warn("Failed to get properties for instance: ", instance.Name)
					props = {}
				end

				table.insert(dirChildren, {
					type = "file",
					name = "init.meta.json",
					content = serde.encode("json", {
						["name"] = instance.Name,
						["className"] = instance.ClassName,
						["properties"] = props
					})
				})
			end
		end

		for _, child in children do
			local nodeSuccess, node = pcall(function()
				return Tree.constructInstanceTreeFromInstance(child)
			end)
			if not nodeSuccess then
				print("Could not construct instance tree for child:", child.Name, child.ClassName)
				print(node)
				continue
			end
			table.insert(dirChildren, node)
		end

		if hasTags or hasAttributes then
			local metaExists = false
			for _, child in dirChildren do
				if child.name == "init.meta.json" then
					metaExists = true
					break
				end
			end
			if not metaExists then
				table.insert(dirChildren, {
					type = "file",
					name = "init.meta.json",
					content = serde.encode("json", {
						["name"] = instance.Name,
						["properties"] = Tree.getInstanceProperties(instance)
					})
				})
			end
		end

		return {
			type = "directory",
			name = instance.Name,
			children = dirChildren
		}
	end
end

function Tree.constructInstanceTreeFromDirectory(
	dirPath: string
): TreeNode
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
			if childPath:find(PACKAGE_META_FILE) then
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
			elseif childPath:find(".meta.rbxmx") then
				table.insert(dirChildren, {
					type = "binaryfile",
					name = childName,
					content = content
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
	local packageRevisionId: string? = nil

	local packageMetaPath = Util.joinPathParts(dirPath, PACKAGE_META_FILE)
	if fs.isFile(packageMetaPath) then
		local packageData = fs.readFile(packageMetaPath)
		local packageJson = serde.decode("json", packageData)
		packageAssetId = packageJson["packageAssetId"]
		packageRevisionId = packageJson["packageRevisionId"]
	end

	if dirPath:sub(-1) == "/" then
		dirPath = dirPath:sub(1, -2)
	end

	local nameParts = dirPath:split("/")
	local lastPart = nameParts[#nameParts]

	return {
		type = "directory",
		name = lastPart,
		packageAssetId = packageAssetId,
		packageRevisionId = packageRevisionId,
		children = dirChildren
	}
end

function Tree.constructInstanceFromTreeNode(
	node: TreeNode,
	root: Instance?
): Instance
	if node.type == "directory" then
		local initScriptNode: TreeNode? = nil
		local initMetaNode: TreeNode? = nil
		local initBinaryMetaNode: TreeNode? = nil
		local childrenRef = {}
		
		if node.children then
			for _, childNode in node.children do
				if childNode.name == "init.client.luau" or childNode.name == "init.server.luau" or childNode.name == "init.luau" then
					initScriptNode = childNode
				elseif childNode.name == "init.meta.json" then
					initMetaNode = childNode
				elseif childNode.name == "init.meta.rbxmx" then
					initBinaryMetaNode = childNode
				else
					table.insert(childrenRef, childNode)
				end
			end
		end

		if initScriptNode then
			local scriptClassName = Util.getScriptTypeFromName(initScriptNode.name)
			if scriptClassName then
				local scriptInstance = roblox.Instance.new(scriptClassName)
				scriptInstance.Name = node.name
				scriptInstance.Source = initScriptNode.content or ""

				if not root then
					root = scriptInstance
				end
				
				for _, childNode in childrenRef do
					local childInstance = Tree.constructInstanceFromTreeNode(childNode, root)
					childInstance.Parent = scriptInstance
				end

				if initMetaNode then
					local metaJson = serde.decode("json", initMetaNode.content or "{}")
					local name = metaJson["name"] or node.name
					scriptInstance.Name = name
					local properties = metaJson["properties"] or {}
					Tree.addInstanceProperties(scriptInstance, properties)
				end
				
				return scriptInstance
			else
				error("Invalid init script node for directory: " .. node.name)
			end
		else
			if initMetaNode then
				local metaJson = serde.decode("json", initMetaNode.content or "{}")
				local className = metaJson["className"] or "Folder"
				local name = metaJson["name"] or node.name
				local instance = roblox.Instance.new(className)
				instance.Name = name

				if not root then
					root = instance
				end
				
				local properties = metaJson["properties"] or {}
				Tree.addInstanceProperties(instance, properties)
				
				for _, childNode in childrenRef do
					local childInstance = Tree.constructInstanceFromTreeNode(childNode, root)
					childInstance.Parent = instance
				end
				
				return instance
			elseif initBinaryMetaNode then
				local models = roblox.deserializeModel(initBinaryMetaNode.content or "")
				if #models == 0 then
					error("Deserialized model is empty for binaryfile node: " .. node.name)
				end
				local rootInstance = models[1]

				if not root then
					root = rootInstance
				end
				
				for _, childNode in childrenRef do
					local childInstance = Tree.constructInstanceFromTreeNode(childNode, root)
					childInstance.Parent = rootInstance
				end
				
				return rootInstance
			else
				local folder = roblox.Instance.new("Folder")
				folder.Name = node.name

				if not root then
					root = folder
				end

				for _, childNode in childrenRef do
					local childInstance = Tree.constructInstanceFromTreeNode(childNode, root)
					childInstance.Parent = folder
				end
				
				return folder
			end
		end
	elseif node.type == "file" then
		if node.name:find(".meta.json") then
			local metaJson = serde.decode("json", node.content or "{}")
			local className = metaJson["className"] or "Folder"
			local name = metaJson["name"] or node.name:gsub("%.meta%.json$", "") -- filter for meta
			local instance = roblox.Instance.new(className)
			instance.Name = name 

			if not root then
				root = instance
			end
			
			local properties = metaJson["properties"] or {}
			Tree.addInstanceProperties(instance, properties)
			
			return instance
		else
			local isScript = false
			local scriptClassName = ""
			
			for className, extension in SCRIPT_EXTENSIONS do
				if node.name:find(extension .. "$") then -- filter
					isScript = true
					scriptClassName = className
					break
				end
			end
			
			if isScript then
				local scriptInstance = roblox.Instance.new(scriptClassName)
				scriptInstance.Name = node.name:gsub("%..-$", "")
				scriptInstance.Source = node.content or ""

				if not root then
					root = scriptInstance
				end

				return scriptInstance
			else
				error("Unknown file type for node: " .. node.name)
			end
		end
	elseif node.type == "binaryfile" then
		if node.name:find("%.meta%.rbxmx$") then
			local models = roblox.deserializeModel(node.content or "")
			if #models == 0 then
				error("Deserialized model is empty for binaryfile node: " .. node.name)
			end
			local rootInstance = models[1]

			if not root then
				root = rootInstance
			end

			return rootInstance
		else
			error("Unknown binary file type for node: " .. node.name)
		end
	else
		error("Unknown TreeNode type: " .. tostring(node.type))
	end
end

function Tree.resolveRootPropertyRefs(root: Instance)
    local function resolveRec(instance: Instance)
        Tree.resolvePropertyRefs(instance, root)
        for _, child in instance:GetChildren() do
            resolveRec(child)
        end
    end
    resolveRec(root)
end

function Tree.writeInstanceTreeToFS(
	tree: TreeNode, 
	basePath: string, 
	clearOld: boolean
)
	if clearOld then
		local dirPath = Util.joinPathParts(basePath, Util.safeDirName(tree.name))
		if fs.isDir(dirPath) then
			Util.info("Clearing old version")
			for _, item in fs.readDir(dirPath) do
				local itemPath = Util.joinPathParts(dirPath, item)
				if fs.isDir(itemPath) then
					fs.removeDir(itemPath)
				else
					fs.removeFile(itemPath)
				end
			end
		end
	end

	if tree.type == "directory" then
		local success, err = pcall(function()
			local dirPath = Util.joinPathParts(basePath, Util.safeDirName(tree.name))
			Util.dprint("Writing: ", dirPath)
			fs.writeDir(dirPath)

			if tree.children then
				for _, child in tree.children do
					Tree.writeInstanceTreeToFS(child, dirPath, false)
				end
			end
		end)
		if not success then
			Util.warn("Failed to write directory:", tree.name, "Error:", err)
		end
	elseif tree.type == "file" then
		local success, err = pcall(function()
			local filePath = Util.joinPathParts(basePath, Util.safeDirName(tree.name))
			Util.dprint("Writing: ", filePath)
			if tree.content then
				fs.writeFile(filePath, tree.content)
			else
				Util.warn("File node has no content:", filePath)
			end
		end)
		if not success then
			Util.warn("Failed to write file:", tree.name, "Error:", err)
		end
	elseif tree.type == "binaryfile" then
		local success, err = pcall(function()
			local filePath = Util.joinPathParts(basePath, Util.safeDirName(tree.name))
			Util.dprint("Writing: ", filePath)
			if tree.content then
				fs.writeFile(filePath, tree.content)
			else
				Util.warn("Binary file node has no content:", filePath)
			end
		end)

		if not success then
			Util.warn("Failed to write binary file:", tree.name, "Error:", err)
		end
	end
end

function Tree.constructPackageFromTree(
	tree: TreeNode
): {Instance}
	local instances: {Instance} = {}

	if tree.type ~= "directory" then
		error("Root of the tree must be a directory, misconfigured tree?")
	end

	if (tree.name:find(PACKAGE_ROOT_APPEND .. "$") or tree.name == "") and tree.children then
		for _, child in tree.children do
			local instance = Tree.constructInstanceFromTreeNode(child)
			table.insert(instances, instance)
		end
	else
		local instance = Tree.constructInstanceFromTreeNode(tree)
		table.insert(instances, instance)
	end

	local root = instances[1]
	if not root then
		Util.error("No instances were able to be constructed from tree")
		error("No instances were able to be constructed from tree")
	end
	Tree.resolveRootPropertyRefs(root)

	return instances
end

function Tree.compareTrees(
	oldTree: TreeNode, 
	newTree: TreeNode
): TreeComparisonResult
	local result: TreeComparisonResult = {
		added = {},
		removed = {},
		modified = {},
		moved = {},
		anyChanges = false
	}

	local oldMap: {[string]: TreeNode} = {}
	local newMap: {[string]: TreeNode} = {}

	local fullDiff: string = ""

	local function flattenNode(node: TreeNode, path: string, treeMap: {[string]: TreeNode})
		local currentPath = path == "" and node.name or (Util.joinPathParts(path, node.name))
		treeMap[currentPath] = node
		if node.children then
			for _, child in node.children do
				flattenNode(child, currentPath, treeMap)
			end
		end
	end

	flattenNode(oldTree, "", oldMap)
	flattenNode(newTree, "", newMap)

	local maybeRemoves: {{path: string, node: TreeNode}} = {}
	local maybeAdds: {{path: string, node: TreeNode}} = {}

	for path, oldNode in oldMap do
		local newNode = newMap[path]
		if not newNode then
			table.insert(maybeRemoves, {path = path, node = oldNode})
		else
			local changed = false
			if oldNode.type ~= newNode.type then
				changed = true
			elseif oldNode.type == "file" then
				if oldNode.content ~= newNode.content then
					changed = true
				end
			elseif oldNode.type == "directory" then
				if oldNode.packageAssetId ~= newNode.packageAssetId then
					changed = true
				end
			end

			if changed then
				table.insert(result.modified, {path = path, node = newNode, oldContent = oldNode.content})
				if Util.DebugMode then
					local changes = DMPLib.diff_main(oldNode.content or "", newNode.content or "")
					DMPLib.diff_cleanupSemantic(changes)
					local patch = DMPLib.patch_toText(DMPLib.patch_make(oldNode.content or "", changes))
					fullDiff ..= "--- " .. path .. "\n" .. "+++ " .. path .. "\n" .. patch .. "\n\n"
				end
				result.anyChanges = true
			end
		end
	end

	for path, newNode in newMap do
		if not oldMap[path] then
			table.insert(maybeAdds, {path = path, node = newNode})
			result.anyChanges = true
		end
	end

	local usedAdds = {}

	for _, rem in maybeRemoves do
		local foundMove = false
		for i, add in maybeAdds do
			if usedAdds[i] then continue end
			
			if rem.node.name == add.node.name and rem.node.type == add.node.type then
				local contentMatch = true
				if rem.node.type == "file" then
					contentMatch = rem.node.content == add.node.content
				end
				
				if contentMatch then
					table.insert(result.moved, {
						oldPath = rem.path,
						newPath = add.path,
						node = add.node
					})
					usedAdds[i] = true
					foundMove = true
					result.anyChanges = true
					break
				end
			end
		end
		
		if foundMove == false then
			table.insert(result.removed, rem)
			result.anyChanges = true
		end
	end

	for i, add in maybeAdds do
		if not usedAdds[i] then
			table.insert(result.added, add)
			result.anyChanges = true
		end
	end

	if Util.DebugMode then
		if fullDiff ~= "" then
			fs.writeFile("packageDiff.diff", fullDiff)
		end
	end

	return result
end

return Tree