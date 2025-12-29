--!nonstrict
--// API
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local net = require("@lune/net")
local process = require("@lune/process")
local fs = require("@lune/fs")

local Util = require("./Util")
local Config = require("./Config")

--// Types
export type URLMethod = "GET" | "POST" | "PATCH" | "PUT" | "DELETE"
export type URL = {
	url: string,
	method: URLMethod,
}

export type FormValue = {
	filename: string?,
	contentType: string,
	data: any,
}


--// Constants
local URLS: {[string]: URL} = {
	GET_META = {
		url = "https://apis.roblox.com/assets/v1/assets/{ASSET_ID}",
		method = "GET"
	},
	GET_META_BY_VERSION = {
		url = "https://apis.roblox.com/assets/v1/assets/{ASSET_ID}/versions/{VERSION_NUMBER}",
		method = "GET"
	},
	GET_CONTENT = {
		url = "https://apis.roblox.com/asset-delivery-api/v1/assetId/{ASSET_ID}",
		method = "GET"
	},
	GET_CONTENT_BY_VERSION = {
		url = "https://apis.roblox.com/asset-delivery-api/v1/assetId/{ASSET_ID}/version/{VERSION_NUMBER}",
		method = "GET"
	},
	GET_VERSIONS = {
		url = "https://apis.roblox.com/assets/v1/assets/{ASSET_ID}/versions",
		method = "GET"
	},
	UPDATE_CONTENT = {
		url = "https://apis.roblox.com/assets/v1/assets/{ASSET_ID}",
		method = "PATCH"
	},
	GET_OPERATION_RESULT = {
		url = "https://apis.roblox.com/assets/v1/operations/{OPERATION_ID}",
		method = "GET"
	}
}

--// Vars
local ApiKey: string? = nil

--// Module

local API = {}
API.URLS = URLS

function API.getApiKey(): string
	if ApiKey then
		return ApiKey
	end

	local secrets = Config.get("secrets") :: Config.SecretsConfig?
	if secrets == nil then
		error("No secrets configuration found!")
	end

	if secrets.secretsType == "env" then
		local envKeyName: string? = secrets.secretsEnvKey
		if envKeyName == nil then
			error("No environment key was configured for the API Key!")
		end

		local envKeyValue: string? = process.env[envKeyName]
		if envKeyValue == nil then
			error("No API key found in environment: " .. envKeyName)
		end

		ApiKey = envKeyValue
		return envKeyValue
	elseif secrets.secretsType == "file" then
		local keyName: string? = secrets.secretsFile
		if keyName == nil then
			error("No API Key file was configured!")
		end
		local secretsDir: string? = secrets.secretsDirectory
		if secretsDir == nil then
			error("Configured secrets directory does not exist!")
		end

		local keyPath = Util.joinPathParts(secretsDir, keyName)

		if fs.isFile(keyPath) then
			local fileKey = fs.readFile(keyPath)
			ApiKey = fileKey
			return fileKey
		else
			error("No API key found! Expected at path: " .. keyPath)
		end
	else
		error("Invalid secrets type!")
	end
end

function API.makeRequest(
	urlData: URL, 
	replacements: {[string]: string}?, 
	body: string?, 
	extraHeaders: {[string]: string}?
): (number, string)
	local url = urlData.url
	if replacements then
		for key, value in replacements do
			url = string.gsub(url, "{" .. key .. "}", value)
		end
	end

	local headers = {
		["x-api-key"] = API.getApiKey(),
	}
	if extraHeaders then
		for key, value in extraHeaders do
			headers[key] = value
		end
	end

	if body then
		headers["Content-Type"] = "application/json"
	end

	Util.dprint("Making request to URL:", url)
	local response = net.request({
		method = urlData.method,
		url = url,
		headers = headers,
		body = body,
	})

	if response.statusCode ~= 200 then
		Util.dprint("Request to URL failed:", url)
		Util.dprint("Status Code:", response.statusCode)
		Util.dprint("Response Body:", response.body)
	end

	return response.statusCode, response.body
end

function API.makeAdvRequest(
	url: string,
	method: URLMethod,
	headers: {[string]: string}?,
	body: string?,
	form: {[string]: FormValue}?
): (number, string)
	local finalHeaders = {
		["x-api-key"] = API.getApiKey(),
	}
	if not body then
		body = ""
	end

	if headers then
		for key, value in headers do
			finalHeaders[key] = value
		end
	end

	if form then
		finalHeaders["Content-Type"] = "multipart/form-data"
		local boundaryExt = Util.randomIntOfLength(16)
		local boundary = "-----------------APIBoundary" .. tostring(boundaryExt)
		finalHeaders["Content-Type"] = "multipart/form-data; boundary=" .. boundary

		local parts = {}

		for key, formValue in form do
			table.insert(parts,
	
				Util.stringCombine({
					"--" .. boundary .. "\r\n",
					'Content-Disposition: form-data; name="' .. key .. '"' .. (formValue.filename and ('; filename="' .. formValue.filename .. '"') or "") .. "\r\n",
					"Content-Type: " .. formValue.contentType .. "\r\n",
					"" .. "\r\n",
					tostring(formValue.data),
					"\r\n",
				}, "")
			)
		end

		table.insert(parts, "--" .. boundary .. "--\r\n")
		body = table.concat(parts)
		if body then
			finalHeaders["Content-Length"] = tostring(#body)
		end
	end

	local response = net.request({
		method = method,
		url = url,
		headers = finalHeaders,
		body = body,
	})

	return response.statusCode, response.body
end

return API