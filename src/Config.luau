--!nonstrict
--// Connig
--// Author: okzyrox
--/ Date: 2025/12/19

--// Modules
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local Util = require("./Util")

--// Types

export type ConfigOption = 
	"outputDirectory" |
	"debugLogs"

export type Config = {
	[ConfigOption]: any
}

--// Constants
local PACKAGE_CONFIG_FILE = "repackage.config.json"

local DEFAULT_CONFIG: Config = {
	outputDirectory = "output/",
	debugLogs = false,
}

--// Vars
local UserConfig: Config = DEFAULT_CONFIG

--// Module

local Config = {}

function Config.loadConfig(): Config
	local exists = fs.isFile(PACKAGE_CONFIG_FILE)
	if not exists then
		Util.dprint("No config file found, creating...")
		local defaultConfigJson = serde.encode("json", DEFAULT_CONFIG, true)
		fs.writeFile(PACKAGE_CONFIG_FILE, defaultConfigJson)
		return DEFAULT_CONFIG
	end

	local content = fs.readFile(PACKAGE_CONFIG_FILE)
	local success, parsedConfig = pcall(function()
		local configContent = serde.decode("json", content)
		return configContent
	end)

	if not success then
		Util.dprint("Failed to read config, using default.")
		return DEFAULT_CONFIG
	end

	for key, value in parsedConfig do
		UserConfig[key] = value
	end

	local configNeededUpdate = false 

	for key, value in DEFAULT_CONFIG do
		if parsedConfig[key] == nil then
			configNeededUpdate = true
			UserConfig[key] = value
		end
	end

	if configNeededUpdate == true then
		print("Updating config...")
		fs.writeFile(PACKAGE_CONFIG_FILE, serde.encode("json", UserConfig, true))
	end

	return UserConfig
end

function Config.getConfig(): Config
	return UserConfig
end

function Config.get(key: ConfigOption): any?
	local success, value = pcall(function()
		return UserConfig[key]
	end)

	if success then
		return value
	else
		return nil
	end
end

function Config.getOrDefault(key: ConfigOption): any
	local value = Config.get(key)
	if value == nil then
		return DEFAULT_CONFIG[key]
	else
		return value
	end
end

return Config