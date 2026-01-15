--!nonstrict
--// Repackage - Package Manager
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

local Tree = require("./Tree")
local Util = require("./Util")
local Config = require("./Config")
local RobloxAPI = require("./RobloxAPI")

local formatted = require("./Lib/formatted")

--// Types

type Argument = {
	name: string,
	type: "string" | "number" | "boolean" | "options",
	optional: boolean?,

	options: {string}?
}

type Command = {
	args: {Argument},
	aliases: {string}?,
	desc: string?,
	func: (...any) -> ()?
}

--// Constants
local COMMAND_LIST_PADDING = 12

--// Functions

local function promptContinue(
	message: string
): boolean
	stdio.write(formatted(message .. " (y/n): ", "light_yellow"))
	local input = stdio.readLine()
	local lowered = input:lower()
	lowered = lowered:gsub("\r", ""):gsub("\n", "")
	if #lowered == 0 then
		return false
	end

	return lowered == "y" or lowered == "yes"
end

local function getAssetFromString(
	assetStr: string
): RobloxAPI.RequestedAsset
	if assetStr:find("@") then
		local parts = assetStr:split("@")
		local assetIdStr = parts[1]
		local revisionIdStr = parts[2]

		local assetId = tonumber(assetIdStr)
		local revisionId = tonumber(revisionIdStr)

		if assetId == nil then
			error("Invalid asset ID: " .. assetIdStr)
		end

		if revisionId == nil then
			Util.error("Invalid revision ID: `" .. revisionIdStr .. "`")
			print("The proper format for asset revisions is: " .. formatted("<assetId>", "yellow") .. formatted("@", "magenta") .. formatted("<revisionId>", "yellow"))
            print("For example: " .. formatted("12345678900@3", "light_green"))
			error("")
		end

		return RobloxAPI.asset(
			assetId,
			revisionId
		)
	else
		local assetId = tonumber(assetStr)
		if assetId == nil then
			error("Invalid asset ID: " .. assetStr)
		end

		return RobloxAPI.asset(assetId)
	end
end

local function createPackage(
	assetString: string
)	
	local asset = getAssetFromString(assetString)
	local packageName, tree = RobloxAPI.getPackageTree(asset)
	if not tree or not packageName then
		Util.error("Failed to retrieve package tree.")
		return
	end
	local outDir = Config.get("outputDirectory")
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	local packageOutDirExists = RobloxAPI.getLocalPackagePath(packageName)
	if packageOutDirExists then
		print(
			formatted("Package already downloaded! If you want to update the local package then use the", "yellow"),
		 	formatted("update", "magenta"),
		 	formatted("command.", "yellow")
		)
		return
	end

	local packageOutDir = Util.joinPathParts(outDir, Util.safeDirName(packageName .. ".Package"))
	local packageMetaFile = Util.joinPathParts(packageOutDir, Tree.PACKAGE_META_FILE_PATH)

	Tree.writeInstanceTreeToFS(tree, outDir, true)
	fs.writeFile(packageMetaFile, serde.encode("json", tree, true))

	Util.info("Package created at:", packageOutDir, asset.assetRevisionId and formatted(" (Revision: " .. asset.assetRevisionId .. ")", "grey") or "")
end

local function updateLocalPackage(
	packageName: string
)
	local outDir = Config.get("outputDirectory")
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return
	end
	local packageMetaPath = Util.joinPathParts(packagePath, Tree.PACKAGE_META_FILE_PATH)
	if not fs.isFile(packageMetaPath) then
		Util.warn("Package meta file not found in package folder:", packageMetaPath)
		return
	end
	local packageMetaContent = fs.readFile(packageMetaPath)
	local success, packageData = pcall(function()
		return serde.decode("json", packageMetaContent)
	end)
	if not success then
		Util.warn("Could not read package meta at path:", packageMetaPath)
		return
	end

	local anyChanges, _changes, _state = RobloxAPI.getPackageChanges(packageName)
	if anyChanges then
		print(
			formatted("Local package has modifications, updating will overwrite those changes", "yellow"),
			formatted("if", "yellow", nil, {"bold"}),
			formatted("there is a newer version available.", "yellow")
		)
		print(
			formatted("You can view the changes via the", "grey"),
		 	formatted("diff", "magenta"),
		 	formatted("command.", "grey")
		)
		local proceed = promptContinue("Do you want to continue with the update?")
		if not proceed then
			print(formatted("Update cancelled.", "red"))
			return
		end
	end

	local assetId: string = packageData["packageAssetId"]
	local packageRevisionId: string? = packageData["packageRevisionId"]
	local asset = RobloxAPI.asset(assetId)

	local packageNameNew, treeNew = RobloxAPI.getPackageTree(asset)
	if not treeNew or not packageNameNew then
		Util.error("Failed to retrieve updated package tree.")
		return
	end

	local newRevisionId: string? = treeNew.packageRevisionId
	if packageRevisionId == newRevisionId then
		print(formatted("Package is already up to date", "grey"))
		return
	end
	
	Tree.writeInstanceTreeToFS(treeNew, outDir, true)
	fs.writeFile(packageMetaPath, serde.encode("json", treeNew, true))
	print(formatted("Package updated successfully", "green"))
end

local function getPackageInfo(
	packageName: string
)
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return
	end

	local tree = Tree.constructInstanceTreeFromDirectory(packagePath)

	print(formatted("Details:", "green"))
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
	local subpackages = Tree.getDescendantsByClass(tree, "PackageLink")
	if #subpackages > 0 then
		Util.warn("Package:", packageName, "contains sub-packages which are not supported.")
		print(" Sub-packages:")
		for _, subpackage in subpackages do
			local content = serde.decode("json", subpackage.content)
			print("  -", "Package", "(Asset ID:", (content.PackageId or "N/A") .. ")")
		end
	end

	local totalItems = Util.tableCount(Tree.getDescendants(tree))
	local proceed = promptContinue("List the package contents (and any References)" .. (" (" .. totalItems .. " items)"))
	if not proceed then
		return
	end

	local package, refsResolved = Tree.constructPackageFromTree(tree)

	if not refsResolved then
		local proceedRefs = stdio.prompt("confirm", "View contents?")
		if not proceedRefs then
			return
		end
	end
	print(formatted("Contents:", "cyan"))
	for i, packageItem in package do
		stdio.write("[" .. i .. "]")
		Util.printInstance(packageItem, " ")
	end
end

local function getPackageRevisions(
	assetId: string
)	
	local asset = RobloxAPI.asset(assetId)
	local meta = RobloxAPI.getAssetMeta(asset)
	if not meta then
		Util.warn("Could not get package meta for asset with ID:", asset.assetId)
		return
	end

	local versionsResponse = RobloxAPI.getPackageVersions(asset)
	local assetVersions = {}
	for _, versionData in versionsResponse["assetVersions"] do
		local basePath: string = versionData["path"]
		local pathParts = basePath:split("/")
		local versionNumberStr = pathParts[#pathParts]
		local versionDate = versionData["createTime"]
		local versionPublished = versionData["published"]

		table.insert(assetVersions, {
			revisionId = tonumber(versionNumberStr),
			revisionDate = versionDate,
			isPublished = versionPublished
		})
	end

	print("Latest Revisions for", meta["displayName"])
	for _, versionInfo in assetVersions do
		print(
			formatted(" Revision: " .. versionInfo.revisionId, "yellow"),
			formatted("| Date: " .. versionInfo.revisionDate, "grey"),
			formatted(versionInfo.isPublished and "| Published" or "", "green")
		)
	end
end

local function getPackageDiff(
	packageName: string
)
	local anyChanges, changes, state = RobloxAPI.getPackageChanges(packageName)

	if state == "Outdated" then
		print(formatted("Local package is outdated, update by re-downloading.", "yellow"))
	end

	if state == "None" then
		return
	end

	if anyChanges == false then
		print(formatted("No changes", "grey"))
	else
		if state == "Modified" then
			print("Local package has been modified.")
		end
		if #changes.added > 0 then
			print("Added:")
			for _, added in changes.added do
				print(formatted(" + " .. added.path, "green"))
			end
		end

		if #changes.removed > 0 then
			print("Removed:")
			for _, removed in changes.removed do
				print(formatted(" - " .. removed.path, "red"))
			end
		end

		if #changes.modified > 0 then
			print("Modified:")
			for _, modified in changes.modified do
				print(formatted(" * " .. modified.path, "yellow"))
			end
		end

		if #changes.moved > 0 then
			print("Moved:")
			for _, moved in changes.moved do
				print(formatted(" * " .. moved.oldPath, "red") .. " -> " .. formatted(moved.newPath, "green"))
			end
		end
	end
end

local function savePackage(
	packageName: string,
	outputFile: string
)
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return
	end

	if fs.isFile(outputFile) then
		Util.warn("An output file with that name already exists!")
		return
	end

	local cleanOutputFile = Util.safeDirName(outputFile)
	if fs.isFile(cleanOutputFile) then
		Util.warn("An output file with that name already exists!")
		return
	end

	local tree = Tree.constructInstanceTreeFromDirectory(packagePath)
	local package, refsResolved = Tree.constructPackageFromTree(tree)
	local rbxmData = roblox.serializeModel(package, false)

	fs.writeFile(cleanOutputFile, rbxmData)
	print("Package saved to file:", cleanOutputFile)
end

local function publishPackage(
	packageName: string
)
	local publishStatus, operationId = RobloxAPI.publishToPackage(packageName)
	if publishStatus == "SUCCESS" then
		Util.info("Package published successfully:", packageName)
	elseif publishStatus == "FAILED" then
		Util.error("Failed to publish package:", packageName)
	elseif publishStatus == "PENDING" then
		print(formatted("Package publish is pending. Operation ID: " .. tostring(operationId), "yellow"))

		local shouldWait = Config.getOrDefault("publishAwaitOperation")
		if not shouldWait then
			return
		end

		local monitorDelay = 15.0
		local result = nil
		while true do
			result = RobloxAPI.checkOperationStatus(operationId)
			if result == true then
				print(formatted("Package published successfully: " .. packageName, "green"))
				break
			elseif result == false then
				print("Pending...")
			elseif result == nil then
				Util.error("Failed to publish package: " .. packageName)
				break
			end

			task.wait(monitorDelay)
		end

		if result == true then
			local packageMeta = RobloxAPI.getPackageMeta(packageName)
			if packageMeta == nil then
				Util.warn("Could not retrieve package meta after publish.")
				return
			end

			-- generational code
			local latestRevisionId = tonumber(packageMeta["revisionId"] or "0") or 0
			if latestRevisionId == 0 then
				Util.warn("Could not determine new revision ID after publish.")
				return
			end
			local updated = RobloxAPI.updateLocalPackageMeta(
				packageName, 
				latestRevisionId
			)

			if updated then
				print(formatted("Updated package meta to revision: " .. latestRevisionId, "green"))
			else
				Util.warn("Failed to update package meta to new revision:", latestRevisionId)
			end
		end
	end
end

local function setup()
	Config.loadConfig(true)

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
			formatted(secrets.secretsEnvKey or "ROBLOX_API_KEY", "light_green")
		)
	end

	print(formatted("When creating an API key, ensure it has the following permissions:", "yellow"))
	print(formatted("  - asset:read", "green"))
	print(formatted("  - asset:write", "green"))
	print(formatted("  - legacy-asset:manage", "green"))

	print("Set-up the current working directory for use with Repackage")
end

local function showHelp(
	commands: {[string]: Command}
)
	print(formatted("Repackage - A Package Manager", "light_cyan", nil, {"bold"}))
	print(formatted("Usage: Repackage <command> [args...]", "light_magenta", nil, {"bold"}))
	print(formatted("Commands:", "light_cyan", nil, {"bold"}))
	for commandName, commandData in commands do
		stdio.write("  " .. formatted(commandName, "light_green", nil, {"underline"}))
		if commandData.desc then
			local i = 0
			while i < (COMMAND_LIST_PADDING - #commandName) do
				stdio.write(" ")
				i += 1
			end
			stdio.write(formatted(commandData.desc, "light_yellow") .. "\n")
		else
			stdio.write("\n")
		end
	end
end

local function showHelpCommand(
	commandName: string,
	commandData: Command
)
	print(formatted("Command: " .. commandName, "light_cyan", nil, {"bold"}))
	if commandData.desc then
		print(formatted("Description: " .. commandData.desc, "light_yellow"))
	end
	if commandData.aliases and #commandData.aliases > 0 then
		print(formatted("Aliases: " .. table.concat(commandData.aliases, ", "), "light_green"))
	end
	if #commandData.args > 0 then
		print(formatted("Arguments:", "light_magenta"))
		for _, argData in commandData.args do
			local argLine = " - " .. argData.name .. " (" .. argData.type .. ")"
			if argData.optional == true then
				argLine ..= " [Optional]"
			end
			if argData.type == "options" and argData.options then
				argLine ..= " Options: {" .. table.concat(argData.options, ", ") .. "}"
			end
			print(formatted(argLine, "grey"))
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
		args = {
			{
				name = "Package Asset ID / Package Asset String",
				type = "string"
			}
		},
		desc = "Create a package onto the filesystem from a package asset",
		func = createPackage
	},
	update = {
		args = {
			{
				name = "Package Name",
				type = "string"
			}
		},
		desc = "Update a local package to the latest version available on Roblox",
		func = updateLocalPackage
	},
	publish = {
		args = {
			{
				name = "Package Name",
				type = "string"
			}
		},
		desc = "Publish local package changes to the package asset",
		func = publishPackage
	},
	info = {
		args = {
			{
				name = "Package Name",
				type = "string"
			}
		},
		desc = "Get information about a local package",
		func = getPackageInfo
	},
	revisions = {
		args = {
			{
				name = "Package Asset ID",
				type = "number"
			}
		},
		desc = "List revisions for a package asset",
		func = getPackageRevisions
	},
	diff = {
		args = {
			{
				name = "Package Name",
				type = "string"
			}
		},
		desc = "Get differences between local package and the current uploaded package asset",
		func = getPackageDiff
	},
	save = {
		args = {
			{
				name = "Package Name",
				type = "string"
			}, 
			{
				name = "Output File (.rbxm)",
				type = "string"
			}
		},
		desc = "Save a local package to a .rbxm file",
		func = savePackage
	}
}

Commands.help = {
	args = {
		{
			name = "Command Name",
			type = "string",
			optional = true
		}
	},
	aliases = {
		"-h",
		"--help",
	},
	desc = "Show this help message",
	func = function(commandName: string?)
		if commandName then
			local commandData = Commands[commandName]
			if commandData then
				showHelpCommand(commandName, commandData)
			else
				print(formatted("Unknown command: " .. commandName, "yellow"))
			end
		else
			showHelp(Commands)
		end
	end
}

local function main()
	Config.loadConfig()
	Util.DebugMode = Config.getOrDefault("debugLogs")

	if not (#process.args > 0) then
		showHelp(Commands)
		return
	elseif process.args[1] == nil then
		Util.warn("No command provided!")
		return
	end
	local commandName = process.args[1]
	local aliasCommandName: string? = nil
	for cmdName, cmdData in Commands do
		if cmdData.aliases then
			if table.find(cmdData.aliases, commandName) then
				aliasCommandName = cmdName
				break
			end
		end
	end
	if aliasCommandName then
		commandName = aliasCommandName
	end

	if not Commands[commandName] then
		Util.warn("Unknown command:", commandName)
		return
	else
		local commandData = Commands[commandName]
		local commandArgs = {}
		for i = 1, #commandData.args do
			local argValue = process.args[i + 1]
			local commandArgData = commandData.args[i]
			if not argValue and commandArgData.optional ~= true then
				--/ amazing formatting
				local argMsg = `{formatted("Missing argument: ", "yellow")}{formatted(commandArgData.name, "light_green")}{formatted(" for ", "yellow")}{formatted(commandName, "light_magenta")}`
				if commandArgData.options then
					argMsg ..= `{formatted(" (Options: ", "yellow")}{formatted("{" .. table.concat(commandArgData.options, ", ") .. "}", "light_green")}{formatted("}", "yellow")}`
				end
				print(argMsg)
				return
			end
			
			if commandArgData.type == "number" then
				local success, number = pcall(function()
					return tonumber(argValue)
				end)
				if not success or number == nil then
					Util.warn("Invalid number for argument:", commandArgData.name)
					return
				end
				argValue = number
			elseif commandArgData.type == "boolean" then
				local lowered = tostring(argValue):lower()
				if lowered == "true" then
					argValue = true
				elseif lowered == "false" then
					argValue = false
				else
					Util.warn("Invalid boolean for argument:", commandArgData.name)
					print(formatted("Expected true or false", "yellow"))
					return
				end
			elseif commandArgData.type == "options" then
				if not commandArgData.options then
					return
				end

				if not table.find(commandArgData.options, argValue) then
					local options = table.concat(commandArgData.options, ", ")
					Util.warn("Invalid option for argument:", commandArgData.name)
					print(formatted("Expected one of: " .. options, "light_green"))
					return
				end
			end

			table.insert(commandArgs, argValue)
		end
		if commandData.func then
			commandData.func(table.unpack(commandArgs))
		end
	end
end

main()

