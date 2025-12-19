--!nonstrict
--// Package Manager
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Tree = require("./Tree")
local API = require("./API")
local Util = require("./Util")

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
		
		local v = roblox.deserializeModel(response)
		if #v == 0 then
			print("No instances found in the package content for assetId:", assetId)
			return nil
		end
		local tree = Tree.constructInstanceTreeFromInstance(v[1])
		tree["packageAssetId"] = assetId

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

--// Main
local function debugAsset(assetId: string)
	if Util.DebugMode then
		if not fs.isDir("debug") then
			fs.writeDir("debug")
		end
	end
	local packageName, tree = getPackageTree(assetId)
	if not tree then
		error("Failed to retrieve package tree.")
	end
	local outDir = "output/" .. packageName
	-- if not fs.isDir(outDir) then
	-- 	fs.writeDir(outDir)
	-- end
	-- fs.writeFile(outDir .. "/package.json", serde.encode("json", tree, true))
	-- writeInstanceTreeToFS(tree, outDir)

	local tree2 = Tree.constructInstanceTreeFromDirectory(outDir)
	fs.writeFile("debug/package_from_fs.json", serde.encode("json", tree2, true))
end

local function main()
	if not (#process.args > 0) then
		print("Package Manager")
		print("   Usage: PackageManager <assetId (of a package)>")
		return
	elseif process.args[1] == nil or process.args[1] == "" then
		print("Usage: PackageManager.luau <assetId (of a package)>")
		warn("No assetId provided")
	end
	local assetId = process.args[1]
	debugAsset(assetId)
	
end

main()

