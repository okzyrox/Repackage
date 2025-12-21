--!nonstrict
--// API
--// Author: okzyrox
--/ Date: 2025/12/18

--// Modules
local net = require("@lune/net")
local fs = require("@lune/fs")

local Util = require("./Util")

--// Types
export type URLMethod = "GET" | "POST" | "PATCH" | "PUT" | "DELETE"
export type URL = {
	url: string,
	method: URLMethod,
}

export type PUBLISH_STATE = "NO-CHANGES" | "SUCCESS" | "FAILED"

--// Constants
local PACKAGE_CONTENT_TYPE = "model/x-rbxm"

local URLS: {[string]: URL} = {
	GET_META = {
		url = "https://apis.roblox.com/assets/v1/assets/{ASSET_ID}",
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
API.PACKAGE_CONTENT_TYPE = PACKAGE_CONTENT_TYPE

function API.getApiKey(): string
	if ApiKey then
		return ApiKey
	end

	if fs.isFile("secrets/apikey.txt") then
		local fileKey = fs.readFile("secrets/apikey.txt")
		ApiKey = fileKey
		return fileKey
	else
		error("No API key found! Follow instructions in secrets/apikey.txt.template")
	end
end

function API.makeRequest(urlData: URL, replacements: {[string]: string}?, body: string?, extraHeaders: {[string]: string}?): (number, string)
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

	return response.statusCode, response.body
end

function API.makeAdvRequest(
	url: string,
	method: URLMethod,
	headers: {[string]: string}?,
	body: string?,
	form: {[string]: any}?
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

		local boundary = "----APIFormBoundary" .. tostring(os.clock()):gsub("%.", "")
		finalHeaders["Content-Type"] = "multipart/form-data; boundary=" .. boundary

		local parts = {}

		for key, value in form do
			table.insert(parts,
				"--" .. boundary .. "\r\n" .. 'Content-Disposition: form-data; name="' .. key .. '"\r\n\r\n' .. tostring(value) .. "\r\n"
			)
		end

		table.insert(parts, "--" .. boundary .. "--\r\n")
		body = table.concat(parts)
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