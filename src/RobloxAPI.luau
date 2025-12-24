--!nonstrict
--// RobloxAPI
--// Author: okzyrox
--/ Date: 2025/12/24

--// Modules
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Tree = require("./Tree")
local Util = require("./Util")
local Config = require("./Config")
local API = require("./API")

--// Types
export type PUBLISH_STATE = "NO-CHANGES" | "SUCCESS" | "FAILED" | "PENDING"

--// Constants
local PACKAGE_CONTENT_TYPE = "model/x-rbxm"

--// Module

local RobloxAPI = {}

--/ Get Asset Meta
function RobloxAPI.getAssetMeta(
    assetId: string, 
    versionId: string?
): string?
	local replacements = {ASSET_ID = assetId}
	local urlData: API.URL = API.URLS.GET_META
	if versionId then
		urlData = API.URLS.GET_META_BY_VERSION
		replacements["VERSION_NUMBER"] = tostring(versionId)
	end

	local statusCode, response = API.makeRequest(
		urlData,
		replacements,
		nil
	)

	local jsonResponse = serde.decode("json", response)
	if statusCode == 200 then
		return jsonResponse
	else
		local base = "Failed to get asset meta for assetId:" .. assetId
		if versionId then
			base ..= " with version:" .. versionId
		end
		Util.dprint(base, assetId, "Status Code:", statusCode, "Response:", response)
		return nil
	end
end

--/ Get Package Content Data 
function RobloxAPI.getPackageContent(
    assetId: string, 
    versionId: string?
): string?
	local urlData: API.URL
	local replacements = {ASSET_ID = assetId}

	if versionId then
		urlData = API.URLS.GET_CONTENT_BY_VERSION
		replacements["VERSION_NUMBER"] = tostring(versionId)
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

--/ Get versions of an asset
function RobloxAPI.getPackageVersions(
    assetId: string
): any?
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

--/ Get the TreeNodes of a package asset
function RobloxAPI.getPackageTree(
    assetId: string, 
    versionId: string?
): (string?, Tree.TreeNode?)
	local meta = RobloxAPI.getAssetMeta(assetId, versionId)
	if not meta then
		warn("Could not get package meta for asset with ID:", assetId)
		return nil
	end
	local packageName: string = meta["displayName"]
	local packageRevisionId: string = meta["revisionId"]
	local content: any? = RobloxAPI.getPackageContent(assetId, versionId)
	if content then
		local dataLocation = content["location"]
		local _statusCode, response = API.makeRequest(
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

--/ Get changes between a local package and the current published version
function RobloxAPI.getPackageChanges(
    packageName: string
): (boolean, Tree.TreeComparisonResult?, Tree.TreeState?)
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

	local _treeCurrentName, treeCurrent = RobloxAPI.getPackageTree(packageAssetId)
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

--/ Publish to a package (buggy; incomplete)
function RobloxAPI.publishToPackage(
    packageName: string, 
    _revisionNote: string?
): PUBLISH_STATE
	local outDir = Config.get("outputDirectory")
	local packagePath = Util.joinPathParts(outDir, packageName)
	if not fs.isDir(packagePath) then
		warn("Package not found at path:", packagePath)
		return "FAILED"
	end

	local changes, _c, _s = RobloxAPI.getPackageChanges(packageName)
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
			["Content-Type"] = PACKAGE_CONTENT_TYPE 
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
            return "PENDING"
		else
			print("Package published")
		end

		return "SUCCESS"
	else
		warn("Failed to publish package:", packageName, "Status Code:", statusCode, "Response:", response)
		return "FAILED"
	end
end

return RobloxAPI