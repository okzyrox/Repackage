--!nonstrict
--// Repackage - Package Manager
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local Tree = require("./Tree")
local Util = require("./Util")
local Config = require("./Config")
local RobloxAPI = require("./RobloxAPI")

local colored = require("./Lib/colored")

--// Types
type Command = {
	args: {string},
	desc: string?,
	func: (...any) -> ()?
}

--// Constants
local COMMAND_LIST_PADDING = 12

--// Functions

local function promptContinue(
	message: string
): boolean
	stdio.write(colored(message .. " (y/n): ", "light_yellow"))
	local input = stdio.readLine()
	local lowered = input:lower()
	lowered = lowered:gsub("\r", ""):gsub("\n", "")
	if #lowered == 0 then
		return false
	end

	return lowered == "y" or lowered == "yes"
end

local function createPackage(
	assetId: string
)
	local packageName, tree = RobloxAPI.getPackageTree(assetId)
	if not tree or not packageName then
		print("Failed to retrieve package tree.")
		return
	end
	local outDir = Config.get("outputDirectory")
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	local packageOutDirExists = RobloxAPI.getLocalPackagePath(packageName)
	if packageOutDirExists then
		print(
			colored("Package already downloaded! If you want to update the local package then use the", "yellow"),
		 	colored("update", "magenta"),
		 	colored("command.", "yellow")
		)
		return
	end

	local packageOutDir = Util.joinPathParts(outDir, packageName .. ".Package")
	local packageMetaFile = Util.joinPathParts(packageOutDir, Tree.PACKAGE_META_FILE_PATH)

	Tree.writeInstanceTreeToFS(tree, outDir, true)
	fs.writeFile(packageMetaFile, serde.encode("json", tree, true))

	print("Package created at:", packageOutDir)
end

local function updateLocalPackage(
	packageName: string
)
	local outDir = Config.get("outputDirectory")
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		warn("Package not found with name:", packageName)
		return
	end
	local packageMetaPath = Util.joinPathParts(packagePath, Tree.PACKAGE_META_FILE_PATH)
	if not fs.isFile(packageMetaPath) then
		warn("Package meta file not found in package folder:", packageMetaPath)
		return
	end
	local packageMetaContent = fs.readFile(packageMetaPath)
	local success, packageData = pcall(function()
		return serde.decode("json", packageMetaContent)
	end)
	if not success then
		warn("Could not read package meta at path:", packageMetaPath)
		return
	end

	local anyChanges, _changes, _state = RobloxAPI.getPackageChanges(packageName)
	if anyChanges then
		print(
			colored("Local package has modifications, updating will overwrite those changes", "yellow"),
			colored("if", "yellow", nil, {"bold"}),
			colored("there is a newer version available.", "yellow")
		)
		print(
			colored("You can view the changes via the", "grey"),
		 	colored("diff", "magenta"),
		 	colored("command.", "grey")
		)
		local proceed = promptContinue("Do you want to continue with the update?")
		if not proceed then
			print(colored("Update cancelled.", "red"))
			return
		end
	end

	local assetId: string = packageData["packageAssetId"]
	local packageRevisionId: string? = packageData["packageRevisionId"]
	local packageNameNew, treeNew = RobloxAPI.getPackageTree(assetId)
	if not treeNew or not packageNameNew then
		warn("Failed to retrieve updated package tree.")
		return
	end

	local newRevisionId: string? = treeNew.packageRevisionId
	if packageRevisionId == newRevisionId then
		print(colored("Package is already up to date", "grey"))
		return
	end
	
	Tree.writeInstanceTreeToFS(treeNew, outDir, true)
	fs.writeFile(packageMetaPath, serde.encode("json", treeNew, true))
	print(colored("Package updated successfully", "green"))
end

local function getPackageInfo(
	packageName: string
)
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		warn("Package not found with name:", packageName)
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
		print(" Package Revision: " .. tree.packageRevisionId)
	else
		print(" Package Revision: N/A")
	end
	print(" Root Path: " .. packagePath)
	local package = Tree.constructPackageFromTree(tree)
	local totalItems = Util.tableCount(package)
	local proceed = promptContinue("List the package contents?" .. (" (" .. totalItems .. " items)"))
	if not proceed then
		return
	end

	print(colored("Contents:", "cyan"))
	for i, packageItem in package do
		stdio.write("[" .. i .. "]")
		Util.printInstance(packageItem, " ")
	end
end

local function getPackageRevisions(
	assetId: string
)
	local meta = RobloxAPI.getAssetMeta(assetId)
	if not meta then
		warn("Could not get package meta for asset with ID:", assetId)
		return
	end

	local versionsResponse = RobloxAPI.getPackageVersions(assetId)
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

	print("Latest Revisions for", meta["displayName"])
	for _, versionInfo in assetVersions do
		print(colored(" ID: " .. versionInfo.revisionId .. " | Date: " .. versionInfo.revisionDate, "light_grey"))
	end
end

local function getPackageDiff(
	packageName: string
)
	local anyChanges, changes, state = RobloxAPI.getPackageChanges(packageName)

	if state == "Outdated" then
		print(colored("Local package is outdated, update by re-downloading.", "yellow"))
	end

	if state == "None" then
		return
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

local function publishPackage(
	packageName: string
)
	local publishStatus, operationId = RobloxAPI.publishToPackage(packageName)
	if publishStatus == "SUCCESS" then
		print(colored("Package published successfully: " .. packageName, "green"))
	elseif publishStatus == "FAILED" then
		print(colored("Failed to publish package: " .. packageName, "red"))
	elseif publishStatus == "PENDING" then
		print(colored("Package publish is pending. Operation ID: " .. tostring(operationId), "yellow"))
	end
end

local function setup()
	local outDir = Config.getOrDefault("outputDirectory")
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	local secrets = Config.getOrDefault("secrets") :: Config.SecretsConfig

	if secrets.secretsType == "file" then 
		local secretsDir = secrets.secretsDirectory
		if not fs.isDir(secretsDir) then
			fs.writeDir(secretsDir)
		end

		local secretsFile = secrets.secretsFile
		local secretsFilePath = Util.joinPathParts(secretsDir, secretsFile)
		if not fs.isFile(secretsFilePath) then
			fs.writeFile(secretsFilePath, "REPLACE THIS TEXT WITH YOUR API KEY")
			print("Created secrets file at:", secretsFilePath)
		end
	elseif secrets.secretsType == "env" then
		print(
			"Make sure to set the environment variable:", 
			colored(secrets.secretsEnvKey or "ROBLOX_API_KEY", "light_green")
		)
	end

	print(colored("When creating an API key, ensure it has the following permissions:", "yellow"))
	print(colored("  - asset:read", "green"))
	print(colored("  - asset:write", "green"))
	print(colored("  - legacy-asset:manage", "green"))

	print("Set-up the current working directory for use with Repackage")
end

local function showHelp(
	commands: {[string]: Command}
)
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

--// Main
local Commands: {[string]: Command} = {
	setup = {
		args = {},
		desc = "Setup the current folder for Repackage usage",
		func = setup
	},
	create = {
		args = {"Package Asset ID"},
		desc = "Create a package onto the filesystem from a package asset",
		func = createPackage
	},
	update = {
		args = {"Package Name"},
		desc = "Update a local package to the latest version available on Roblox",
		func = updateLocalPackage
	},
	publish = {
		args = {"Package Name"},
		desc = "Publish local package changes to the package asset",
		func = publishPackage
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
	help = {
		args = {},
		desc = "Show this help message",
	}
}

local HelpAliases = {
	"-h",
	"--help",
	"help"
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
	elseif table.find(HelpAliases, process.args[1]) then
		showHelp(Commands)
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
		if commandData.func then
			commandData.func(table.unpack(commandArgs))
		end
	end
end

main()

