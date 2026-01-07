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
export type PublishState = "NO-CHANGES" | "SUCCESS" | "FAILED" | "PENDING"

export type ModerationState = "Reviewing" | "Approved" | "Rejected"
export type AssetPrivacy = "default" | "restricted" | "openUse"
export type AssetState = "Unspecified" | "Active" | "Archived"

export type Error = {
	code: number,
	message: string
}

export type ContentError = {
	Code: number,
	Message: string,
	CustomErrorCode: number
}

export type Creator = {
	userId: number?,
	groupId: number?,
}

export type CreationContext = {
	assetPrivacy: AssetPrivacy,
	creator: Creator?,
}

export type ModerationResult = {
	moderationState: ModerationState,
}

export type AssetPreview = {
	asset: string,
	altText: string
}

export type ContentRepresentationSpecifier = {
	format: string,
	majorVersion: string,
	fidelity: string
}

export type ContentAssetMetadata = {
	metadataType: number,
	value: string
}

export type AssetMetadata = {
	assetType: string,
	assetId: number,
	creationContext: CreationContext,
	description: string,
	displayName: string,
	path: string,
	revisionId: string,
	revisionCreateTime: string,
	moderationResult: ModerationResult,
	icon: string,
	previews: {AssetPreview},
	state: AssetState,
	socialLink: {}
}

export type AssetVersionMetadata = {
	creationContext: CreationContext,
	path: string,
	moderationResult: ModerationResult,
	published: boolean
}

export type OperationResult<T> = {
	path: string,
	done: boolean,
	error: Error,
	response: T
}

export type ContentResponse = {
	location: string,
	errors: {ContentError},
	requestId: string,
	isArchived: boolean,
	assetTypeId: number,
	contentRepresentationSpecifier: ContentRepresentationSpecifier,
	assetMetadatas: {ContentAssetMetadata},
	isRecordable: boolean
}

export type AssetUpdateResponse = OperationResult<AssetMetadata> & {
	operationId: string
}

export type AssetVersionsResponse = {
	assetVersions: {AssetVersionMetadata},
	nextPageToken: string?
}

--// Constants
local PACKAGE_CONTENT_TYPE = "model/x-rbxm"

--// Module

local RobloxAPI = {}
RobloxAPI.PACKAGE_CONTENT_TYPE = PACKAGE_CONTENT_TYPE

function RobloxAPI.getLocalPackagePath(
	packageName: string
): string?
	local outDir = Config.get("outputDirectory")
	local packagePath = Util.joinPathParts(outDir, packageName)
	if not fs.isDir(packagePath) then
		if Util.stringEndsWith(packagePath, ".Package") then
			return nil
		else
			packagePath = Util.joinPathParts(outDir, packageName .. ".Package")
			if not fs.isDir(packagePath) then
				return nil
			end
		end
	end

	return packagePath
end

--/ Get Asset Meta
function RobloxAPI.getAssetMeta(
    assetId: string, 
    versionId: string?
): AssetMetadata?
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

	local jsonResponse: AssetMetadata = serde.decode("json", response)
	if statusCode == 200 then
		return jsonResponse
	else
		local base = "Failed to get asset meta for assetId: " .. assetId
		if versionId then
			base ..= " with version:" .. versionId
		end
		Util.dprint(base, "Status Code:", statusCode, "Response:", response)
		return nil
	end
end

--/ Get Asset Meta v/ Package
function RobloxAPI.getPackageMeta(
	packageName: string, 
	versionId: string?
): AssetMetadata?
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return nil
	end

	local metaPath = Util.joinPathParts(packagePath, Tree.PACKAGE_META_FILE_PATH)
	local metaContent = fs.readFile(metaPath)
	local success, packageMeta = pcall(function()
		return serde.decode("json", metaContent)
	end)

	if not success then
		Util.warn("Failed to read package meta for package:", packageName)
		return nil
	end

	local assetId: string = packageMeta["packageAssetId"]
	if not assetId then
		Util.warn("Malformed package meta, missing package asset id:", packageName)
		return nil
	end
	return RobloxAPI.getAssetMeta(assetId, versionId)
end

--/ Get Package Content Data 
function RobloxAPI.getPackageContent(
    assetId: string, 
    versionId: string?
): ContentResponse?
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

	local jsonResponse: ContentResponse = serde.decode("json", response)
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
): AssetVersionsResponse?
	local statusCode, response = API.makeRequest(
		API.URLS.GET_VERSIONS,
		{ASSET_ID = assetId},
		nil
	)

	local jsonResponse: AssetVersionsResponse = serde.decode("json", response)
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
		Util.warn("Could not get package meta for asset with ID:", assetId)
		return nil
	end
	local packageName: string = meta["displayName"]
	local packageRevisionId: string = meta["revisionId"]
	local content: ContentResponse? = RobloxAPI.getPackageContent(assetId, versionId)
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
			Util.warn("Unable to deserialize package: ", assetId)
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
			Util.warn("Could not construct instance tree for package:", meta["displayName"])
			-- print(tree)
			return nil
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
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return false, nil, "None"
	end

	local treeNew = Tree.constructInstanceTreeFromDirectory(packagePath)
	local packageAssetId = treeNew.packageAssetId
	if not packageAssetId then
		Util.warn("Package at path does not have a valid asset ID:", packagePath)
		return false, nil, "None"
	end

	local _treeCurrentName, treeCurrent = RobloxAPI.getPackageTree(packageAssetId)
	if not treeCurrent then
		Util.warn("Could not get current package tree for asset:", packageAssetId)
		return false, nil, "None"
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

--/ Publish to a package
function RobloxAPI.publishToPackage(
    packageName: string, 
    _revisionNote: string?
): (PublishState, string?)
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return "FAILED", nil
	end

	local changes, _c, _s = RobloxAPI.getPackageChanges(packageName)
	if changes == false then
		print("No changes to publish for package:", packageName)
		return "NO-CHANGES", nil
	end

	local tree = Tree.constructInstanceTreeFromDirectory(packagePath)
	local package, refsResolved = Tree.constructPackageFromTree(tree)

	if not refsResolved then
		Util.warn("There are unresolved references in the package:", packageName)
		Util.warn("Please resolve all references before publishing.")
		Util.warn("(References to instances outside the package cannot be resolved.)")
		return "FAILED", nil
	end

	local serializedPackage = roblox.serializeModel(package)

	local statusCode, response = API.makeAdvRequest(
		"https://apis.roblox.com/assets/v1/assets/" .. (tree.packageAssetId :: string),
		API.URLS.UPDATE_CONTENT.method,
		{ 
			["Content-Type"] = PACKAGE_CONTENT_TYPE 
		},
		nil,
		{
			request = {
				contentType = "application/json",
				data = serde.encode("json", {
					["assetId"] = tonumber(tree.packageAssetId),
				})
			},
			fileContent = {
				contentType = PACKAGE_CONTENT_TYPE,
				filename = packageName .. ".rbxm",
				data = serializedPackage
			}
		}

	)

	-- print(response)

	if statusCode == 200 then
		local jsonResponse: AssetUpdateResponse = serde.decode("json", response)
		local taskDone = jsonResponse["done"] or false
		local operationId = jsonResponse["operationId"] or nil

		if taskDone == false then
			print("Submitted package to publish")
            return "PENDING", operationId
		else
			print("Package published")
		end

		return "SUCCESS", nil
	else
		Util.warn("Failed to publish package:", packageName, "Status Code:", statusCode, "Response:", response)
		return "FAILED", nil
	end
end

--/ Get package meta from local package
function RobloxAPI.getLocalPackageMeta(
	packageName: string
): Tree.TreeNode?
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return nil
	end

	local metaPath = Util.joinPathParts(packagePath, Tree.PACKAGE_META_FILE_PATH)
	local metaContent = fs.readFile(metaPath)
	local success, packageMeta = pcall(function()
		return serde.decode("json", metaContent)
	end)

	if not success then
		Util.warn("Failed to read package meta for package:", packageName)
		return nil
	end

	return packageMeta
end

--/ Update package meta revision ID in local package
function RobloxAPI.updateLocalPackageMeta(
	packageName: string,
	revisionId: string
): boolean
	local packagePath = RobloxAPI.getLocalPackagePath(packageName)
	if not packagePath then
		Util.warn("Package not found with name:", packageName)
		return false
	end

	local metaFilePath = Util.joinPathParts(packagePath, Tree.PACKAGE_META_FILE_PATH)
	local metaContent = fs.readFile(metaFilePath)
	local success, metaData = pcall(function()
		return serde.decode("json", metaContent)
	end)

	if not success then
		Util.warn("Failed to read package meta for package:", packageName)
		return false
	end

	metaData["packageRevisionId"] = revisionId

	local updatedMetaContent = serde.encode("json", metaData, true)
	fs.writeFile(metaFilePath, updatedMetaContent)
	return true
end

--/ Check operation "done" status
function RobloxAPI.checkOperationStatus(
	operationId: string
): boolean?
	local statusCode, response = API.makeRequest(
		API.URLS.GET_OPERATION_RESULT,
		{OPERATION_ID = operationId},
		nil
	)

	if statusCode == 200 then
		local jsonResponse: OperationResult<AssetMetadata?> = serde.decode("json", response)
		local operationDone = jsonResponse["done"] or false

		if operationDone == false then
			return false
		else
			print("Operation completed:", operationId)
			return true
		end
	else
		Util.warn("Failed to check status for operation:", operationId, "Status Code:", statusCode, "Response:", response)
		return nil
	end
end

return RobloxAPI