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

local colored = require("./Lib/colored")

--// Types

type Command = {
	args: {string},
	desc: string?,
	func: (...any) -> ()
}

--// Constants

local COMMAND_LIST_PADDING = 12

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
		nil
	)

	local jsonResponse = serde.decode("json", response)
	if statusCode == 200 then
		local assetTypeId = jsonResponse["assetTypeId"]
		if assetTypeId ~= 10 then
			print("Requested asset is not a package model!")
			return nil
		end

		return jsonResponse
	else
		print("Failed to get package content for assetId:", assetId, "Status Code:", statusCode, "Response:", response)
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
	local packageRevisionId: string = meta["revisionId"]
	local content: any? = getPackageContent(assetId)
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
			return Tree.constructInstanceTreeFromInstance(deserializedPackage, packageName, assetId, packageRevisionId)
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

local function getPackageChanges(packageName: string): (boolean, Tree.TreeComparisonResult?, Tree.TreeState?)
	local outDir = Config.get("outputDirectory")
	local packagePath = Util.joinPathParts(outDir, packageName)
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

	local state: Tree.TreeState = "Unchanged"

	local changes = Tree.compareTrees(treeCurrent, treeNew)
	if changes.anyChanges == false then
		if tonumber(treeCurrent.packageRevisionId) > tonumber(treeNew.packageRevisionId) then
			state = "Outdated"
		end

		return false, nil, state
	else
		if #changes.added > 0 or #changes.removed > 0 then
			state = "Modified"
		else
			state = "Unchanged"
		end

		if tonumber(treeCurrent.packageRevisionId) > tonumber(treeNew.packageRevisionId) then
			state = "Outdated"
		end

		return true, changes, state
	end
end

local function publishToPackage(packageName: string, revisionNote: string?): API.PUBLISH_STATE
	local outDir = Config.get("outputDirectory")
	local packagePath = Util.joinPathParts(outDir, packageName)
	if not fs.isDir(packagePath) then
		warn("Package not found at path:", packagePath)
		return "FAILED"
	end

	local changes, _c, _s = getPackageChanges(packageName)
	if changes == false then
		print("No changes to publish for package:", packageName)
		return "NO-CHANGES"
	end

	local tree = Tree.constructInstanceTreeFromDirectory(packagePath)
	local package = Tree.constructPackageFromTree(tree)

	local serializedPackage = roblox.serializeModel(package)

	local statusCode, response = API.makeAdvRequest(
		"https://apis.roblox.com/assets/v1/assets/" .. (tree.packageAssetId :: string),
		API.URLS.UPDATE_CONTENT.method,
		{ 
			["Content-Type"] = API.PACKAGE_CONTENT_TYPE 
		},
		nil,
		{
			request = serde.encode("json", {
				["assetId"] = tonumber(tree.packageAssetId),
			}),
			fileContent = serializedPackage
		}

	)

	print(response)

	if statusCode == 200 then
		local jsonResponse = serde.decode("json", response)
		local taskDone = jsonResponse["done"] or false

		if taskDone == false then
			print("Submitted package to publish")
		else
			print("Package published")
		end

		return "SUCCESS"
	else
		warn("Failed to publish package:", packageName, "Status Code:", statusCode, "Response:", response)
		return "FAILED"
	end
end

--// Main
local function create(assetId: string)
	print("Processing...")
	local packageName, tree = getPackageTree(assetId)
	if not tree or not packageName then
		print("Failed to retrieve package tree.")
		return
	end
	local outDir = Config.get("outputDirectory")
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end
	
	Tree.writeInstanceTreeToFS(tree, outDir, true)
	local outDirPackage = Util.joinPathParts(outDir, packageName)

	local packageMetaFile = Util.joinPathParts(outDirPackage, Tree.PACKAGE_META_FILE_PATH)

	fs.writeFile(packageMetaFile, serde.encode("json", tree, true))
	print("Package extracted to:", outDirPackage)
end

local function getPackageInfo(packageName: string)
	local outDir = Config.get("outputDirectory")
	local packagePath = Util.joinPathParts(outDir, packageName)
	if not fs.isDir(packagePath) then
		warn("Package not found at path:", packagePath)
		return
	end

	local tree = Tree.constructInstanceTreeFromDirectory(packagePath)

	print(colored("Details:", "green"))
	print(" Package Name: " .. tree.name)
	if tree.packageAssetId then
		print(" Package Asset ID: " .. tree.packageAssetId)
	else
		print(" Package Asset ID: N/A")
	end
	if tree.packageRevisionId then
		print(" Package Revision ID: " .. tree.packageRevisionId)
	else
		print(" Package Revision ID: N/A")
	end
	print(" Root Path: " .. packagePath)

	local package = Tree.constructPackageFromTree(tree)
	print(colored("Contents:", "cyan"))
	for i, packageItem in package do
		stdio.write("[" .. i .. "]")
		Util.printInstance(packageItem, " ")
	end
end

local function getPackageRevisions(assetId: string)
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
		print(colored(" ID: " .. versionInfo.revisionId .. " | Date: " .. versionInfo.revisionDate, "light_grey"))
	end
end

local function getPackageDiff(packageName: string)
	local anyChanges, changes, state = getPackageChanges(packageName)

	if state == "Outdated" then
		print(colored("Local package is outdated, update by re-downloading.", "yellow"))
	end

	if anyChanges == false then
		print(colored("No changes", "grey"))
	else
		if state == "Modified" then
			print("Local package has been modified.")
		end
		if #changes.added > 0 then
			print("Added:")
			for _, added in changes.added do
				print(colored(" + " .. added.path, "green"))
			end
		end

		if #changes.removed > 0 then
			print("Removed:")
			for _, removed in changes.removed do
				print(colored(" - " .. removed.path, "red"))
			end
		end

		if #changes.modified > 0 then
			print("Modified:")
			for _, modified in changes.modified do
				print(colored(" * " .. modified.path, "yellow"))
			end
		end

		if #changes.moved > 0 then
			print("Moved:")
			for _, moved in changes.moved do
				print(colored(" * " .. moved.oldPath, "red") .. " -> " .. colored(moved.newPath, "green"))
			end
		end
	end
end

local function publish(packageName: string)
	local publishStatus = publishToPackage(packageName)
	if publishStatus == "SUCCESS" then
		print(colored("Package published successfully: " .. packageName, "green"))
	elseif publishStatus == "FAILED" then
		print(colored("Failed to publish package: " .. packageName, "red"))
	end
end

local function debug(assetId: string)
	local content = getPackageContent(assetId)
	print(content)
end

local function setup()
	local outDir = Config.getOrDefault("outputDirectory")
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	print("Setup current working directory for use with Repackager")
end

local function showHelp(commands)
	print(colored("Repackage - Package Manager", "light_cyan", nil, {"bold"}))
	print(colored("Usage: Repackage.luau <command> [args...]", "light_magenta", nil, {"bold"}))
	print(colored("Commands:", "light_cyan", nil, {"bold"}))
	for commandName, commandData in commands do
		stdio.write("  " .. colored(commandName, "light_green", nil, {"underline"}))
		if commandData.desc then
			local i = 0
			while i < (COMMAND_LIST_PADDING - #commandName) do
				stdio.write(" ")
				i += 1
			end
			stdio.write(colored(commandData.desc, "light_yellow") .. "\n")
		else
			stdio.write("\n")
		end
	end
end

local Commands: {[string]: Command} = {
	setup = {
		args = {},
		desc = "Setup the current folder for Repackager usage",
		func = setup
	},
	create = {
		args = {"Package Asset ID"},
		desc = "Create a package onto the filesystem from a package asset",
		func = create
	},
	publish = {
		args = {"Package Name"},
		desc = "Publish local package changes to the package asset (UNFINISHED)",
		func = publish
	},
	info = {
		args = {"Package Name"},
		desc = "Get information about a local package",
		func = getPackageInfo
	},
	revisions = {
		args = {"Package Asset ID"},
		desc = "List revisions for a package asset",
		func = getPackageRevisions
	},
	diff = {
		args = {"Package Name"},
		desc = "Get differences between local package and the current uploaded package asset",
		func = getPackageDiff
	},
	debug = {
		args = {"Package Asset ID"},
		func = debug
	}
}

local function main()
	Config.loadConfig()
	Util.DebugMode = Config.getOrDefault("debugLogs")

	if not (#process.args > 0) then
		showHelp(Commands)
		return
	elseif process.args[1] == nil then
		print(colored("No command provided!", "yellow"))
		return
	elseif not Commands[process.args[1]] then
		print(colored("Unknown command: " .. process.args[1], "yellow"))
		return
	else
		local commandName = process.args[1]
		local commandData = Commands[commandName]
		local commandArgs = {}
		for i = 1, #commandData.args do
			local argValue = process.args[i + 1]
			if not argValue then
				--/ amazing formatting
				local argMsg = `{colored("Missing argument: ", "yellow")}{colored(commandData.args[i], "light_green")}{colored(" for ", "yellow")}{colored(commandName, "light_magenta")}`
				print(argMsg)
				return
			end
			table.insert(commandArgs, argValue)
		end

		commandData.func(table.unpack(commandArgs))
	end
end

main()

