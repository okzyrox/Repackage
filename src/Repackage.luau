--!nonstrict
--// Repackage - Package Manager
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local Tree = require("./Tree")
local API = require("./API")
local Util = require("./Util")
local Config = require("./Config")

--// Types

type Command = {
	args: {string},
	func: (...any) -> ()
}

--// Functions

local function getAssetMeta(assetId: string): string?
	local statusCode, response = API.makeRequest(
		API.URLS.GET_META,
		{ASSET_ID = assetId},
		nil
	)

	local jsonResponse = serde.decode("json", response)
	if statusCode == 200 then
		return jsonResponse
	else
		Util.dprint("Failed to get package meta for assetId:", assetId, "Status Code:", statusCode, "Response:", response)
		return nil
	end
end

local function getPackageContent(assetId: string, versionNumber: number?): string?
	local urlData: API.URL
	local replacements = {ASSET_ID = assetId}

	if versionNumber then
		urlData = API.URLS.GET_CONTENT_BY_VERSION
		replacements["VERSION_NUMBER"] = tostring(versionNumber)
	else
		urlData = API.URLS.GET_CONTENT
	end

	local statusCode, response = API.makeRequest(
		urlData,
		replacements,
		nil,
		{["Accept-Encoding"] = "gzip"}
	)

	if statusCode == 200 then
		return response
	else
		Util.dprint("Failed to get package content for assetId:", assetId, "Status Code:", statusCode, "Response:", response)
		return nil
	end
end

local function getPackageContentV1(assetId: string): any?
	local statusCode, response = API.makeRequest(
		API.URLS.GET_CONTENT_V1_OPENCLOUD,
		{ASSET_ID = assetId},
		nil,
		{
			["Accept-Encoding"] = "gzip",
			["Cookie"] = API.getCookie(),
		}
	)

	local jsonResponse = serde.decode("json", response)
	if statusCode == 200 then
		return jsonResponse
	else
		Util.dprint("Failed to get package content v1 for assetId:", assetId, "Status Code:", statusCode, "Response:", response)
		return nil
	end
end

local function getPackageTree(assetId: string): (string?, any?)
	local meta = getAssetMeta(assetId)
	if not meta then
		warn("Could not get package meta for asset with ID:", assetId)
		return nil
	end
	local packageName: string = meta["displayName"]
	local content: any? = getPackageContentV1(assetId)
	if content then
		local dataLocation = content["location"]
		local statusCode, response = API.makeRequest(
			{
				url = dataLocation,
				method = "GET"
			},
			nil,
			nil,
			{
				["Accept-Encoding"] = "gzip",
				["Cookie"] = API.getCookie(),
			}
		)

		local success, deserializedPackage = pcall(function()
			return roblox.deserializeModel(response)
		end)

		if not success then
			warn("Unable to deserialize package: ", assetId)
			return nil
		end
		
		if #deserializedPackage == 0 then
			print("No instances found in the package content for assetId:", assetId)
			return nil
		end
		
		local treeSuccess, tree = pcall(function()
			return Tree.constructInstanceTreeFromInstance(deserializedPackage, packageName, assetId)
		end)

		if not treeSuccess then 
			warn("Could not construct instance tree for package:", meta["displayName"])
			-- print(tree)
			return nil
		end

		if Util.DebugMode then
			if not fs.isDir("debug") then
				fs.writeDir("debug")
			end
			fs.writeFile("debug/package_tree_from_instance.json", serde.encode("json", tree, true))
		end

		return packageName, tree
	else
		return nil
	end
end

local function getPackageVersions(assetId: string): any?
	local statusCode, response = API.makeRequest(
		API.URLS.GET_VERSIONS,
		{ASSET_ID = assetId},
		nil
	)

	local jsonResponse = serde.decode("json", response)
	if statusCode == 200 then
		return jsonResponse
	else
		Util.dprint("Failed to get package versions for assetId:", assetId, "Status Code:", statusCode, "Response:", response)
		return nil
	end
end

local function getPackageChanges(packageName: string): (boolean, Tree.TreeComparisonResult?)
	local outDir = Config.get("outputDirectory")
	local packagePath = outDir .. packageName
	if not fs.isDir(packagePath) then
		warn("Package not found at path:", packagePath)
		return false
	end

	local treeNew = Tree.constructInstanceTreeFromDirectory(packagePath)
	local packageAssetId = treeNew.packageAssetId
	if not packageAssetId then
		warn("Package at path does not have a valid asset ID:", packagePath)
		return false
	end

	local treeCurrentName, treeCurrent = getPackageTree(packageAssetId)
	if not treeCurrent then
		warn("Could not get current package tree for asset:", packageAssetId)
		return false
	end

	local changes = Tree.compareTrees(treeCurrent, treeNew)
	if changes.anyChanges == false then
		return false, nil
	else
		return true, changes
	end
end

--// Main
local function create(assetId: string)
	print("Processing...")
	local packageName, tree = getPackageTree(assetId)
	if not tree then
		print("Failed to retrieve package tree.")
		return
	end
	local outDir = Config.get("outputDirectory")
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end
	
	Tree.writeInstanceTreeToFS(tree, outDir)
	local outDirPackage = outDir .. "/" .. packageName

	fs.writeFile(outDirPackage .. "/package.json", serde.encode("json", tree, true))
	print("Package extracted to:", outDirPackage)
end

local function getPackage(packageName: string)
	local outDir = Config.get("outputDirectory")
	local packagePath = outDir .. packageName
	if not fs.isDir(packagePath) then
		warn("Package not found at path:", packagePath)
		return
	end

	local tree = Tree.constructInstanceTreeFromDirectory(packagePath)

	print("Details:")
	print(" Package Name: " .. tree.name)
	if tree.packageAssetId then
		print(" Package Asset ID: " .. tree.packageAssetId)
	else
		print(" Package Asset ID: N/A")
	end
	print(" Root Path: " .. packagePath)

	local package = Tree.constructPackageFromTree(tree)
	print("Contents:")
	for i, packageItem in package do
		stdio.write("[" .. i .. "]")
		Util.printInstance(packageItem, " ")
	end
end

local function getRevisions(assetId: string)
	local meta = getAssetMeta(assetId)
	if not meta then
		warn("Could not get package meta for asset with ID:", assetId)
		return
	end

	local versionsResponse = getPackageVersions(assetId)
	local assetVersions = {}
	for _, versionData in versionsResponse["assetVersions"] do
		local basePath: string = versionData["path"]
		local pathParts = basePath:split("/")
		local versionNumberStr = pathParts[#pathParts]
		local versionDate = versionData["createTime"]

		table.insert(assetVersions, {
			revisionId = tonumber(versionNumberStr),
			revisionDate = versionDate,
		})
	end

	print("Revisions for ", meta["displayName"])
	for _, versionInfo in assetVersions do
		print(" ID: " .. versionInfo.revisionId .. " | Date: " .. versionInfo.revisionDate)
	end
end

local function getchanges(packageName: string)
	local anyChanges, changes = getPackageChanges(packageName)

	if anyChanges == false then
		print("No changes")
	else
		if #changes.added > 0 then
			print("Added:")
			for _, added in changes.added do
				print(" + " .. added.path)
			end
		end

		if #changes.removed > 0 then
			print("Removed:")
			for _, removed in changes.removed do
				print(" - " .. removed.path)
			end
		end

		if #changes.modified > 0 then
			print("Modified:")
			for _, modified in changes.modified do
				print(" * " .. modified.path)
			end
		end

		if #changes.moved > 0 then
			print("Moved:")
			for _, moved in changes.moved do
				print(" * " .. moved.oldPath .. " -> " .. moved.newPath)
			end
		end
	end
end

local function setup()
	local outDir = Config.getOrDefault("outputDirectory")
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	print("Setup current working directory for use with Repackager")
end

local Commands: {[string]: Command} = {
	setup = {
		args = {},
		func = setup
	},
	create = {
		args = {"Package Asset ID"},
		func = create
	},
	get = {
		args = {"Package Name"},
		func = getPackage
	},
	getrevisions = {
		args = {"Package Asset ID"},
		func = getRevisions
	},
	getchanges = {
		args = {"Package Name"},
		func = getchanges
	}
}

local function main()
	Config.loadConfig()
	Util.DebugMode = Config.getOrDefault("debugLogs")

	if not (#process.args > 0) then
		print("Package Manager")
		print("Usage: PackageManager.luau <command> [args...]")
		print("Commands:")
		for commandName, commandData in Commands do
			local argsStr = table.concat(commandData.args, "> <")
			print("  " .. commandName .. " <" .. argsStr .. ">")
		end
		return
	elseif process.args[1] == nil then
		warn("No command provided!")
		return
	elseif not Commands[process.args[1]] then
		warn("Unknown command: " .. process.args[1])
		return
	else
		local commandName = process.args[1]
		local commandData = Commands[commandName]
		local commandArgs = {}
		for i = 1, #commandData.args do
			local argValue = process.args[i + 1]
			if not argValue then
				warn("Missing argument <" .. commandData.args[i] .. "> for '" .. commandName .. "'")
				return
			end
			table.insert(commandArgs, argValue)
		end

		commandData.func(table.unpack(commandArgs))
	end
end

main()

