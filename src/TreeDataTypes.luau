--!nonstrict
--// TreeDataTypes
--// Author: okzyrox
--/ Date: 2025/12/26

--// Modules
local roblox = require("@lune/roblox")

local Util = require("./Util")

--// Types

export type DataTypeHandler<T, M> = {
    Ser: (value: T) -> M,
    Des: (data: M) -> T | string,
}

export type MetaAxes = {
    Axes: {string},
}

export type MetaContent = {
    Content: string,
}

export type MetaColor3 = {
    Color3: {number},
}

export type MetaColorSequence = {
    ColorSequence: {
        keypoints: {{time: number, color: {number}}},
    }
}

export type MetaCFrame = {
    CFrame: {
        position: {number},
        orientation: {{number}},
    },
}

export type MetaFont = {
    Font: {
        family: string,
        weight: string,
        style: string,
    },
}

export type MetaInstance = {
    Instance: {
        path: string
    }
}

export type MetaUDim = {
    UDim: {number},
}
export type MetaUDim2 = {
    UDim2: {{number}},
}

export type MetaVector2 = {
    Vector2: {number},
}
export type MetaVector2int16 = {
    Vector2int16: {number},
}
export type MetaVector3 = {
    Vector3: {number},
}
export type MetaVector3int16 = {
    Vector3int16: {number},
}

export type MetaNumberRange = {
    NumberRange: {
        number
    }
}
export type MetaNumberSequence = {
    NumberSequence: {
        keypoints: {{number}},
    }
}

export type Serialisable = 
    Axes |
    Content |
    Color3 |
    ColorSequence |
    CFrame |
    Font |
    Instance |
    UDim |
    UDim2 |
    Vector2 |
    Vector2int16 |
    Vector3 |
    Vector3int16 |
    NumberRange |
    NumberSequence |
    string

export type Deserialisable = 
    MetaAxes |
    MetaContent |
    MetaColor3 |
    MetaColorSequence |
    MetaCFrame |
    MetaFont |
    MetaInstance |
    MetaUDim |
    MetaUDim2 |
    MetaVector2 |
    MetaVector2int16 |
    MetaVector3 |
    MetaVector3int16 |
    MetaNumberRange |
    MetaNumberSequence | 
    string

export type TreeDataTypesT = {
    ["Axes"]: DataTypeHandler<Axes, MetaAxes>,
    ["Content"]: DataTypeHandler<Content, MetaContent>,
    ["Color3"]: DataTypeHandler<Color3, MetaColor3>,
    ["ColorSequence"]: DataTypeHandler<ColorSequence, MetaColorSequence>,
    ["CFrame"]: DataTypeHandler<CFrame, MetaCFrame>,
    ["Font"]: DataTypeHandler<Font, MetaFont>,
    ["Instance"]: DataTypeHandler<Instance, MetaInstance>,
    ["UDim"]: DataTypeHandler<UDim, MetaUDim>,
    ["UDim2"]: DataTypeHandler<UDim2, MetaUDim2>,
    ["Vector2"]: DataTypeHandler<Vector2, MetaVector2>,
    ["Vector2int16"]: DataTypeHandler<Vector2int16, MetaVector2int16>,
    ["Vector3"]: DataTypeHandler<Vector3, MetaVector3>,
    ["Vector3int16"]: DataTypeHandler<Vector3int16, MetaVector3int16>,
    ["NumberRange"]: DataTypeHandler<NumberRange, MetaNumberRange>,
    ["NumberSequence"]: DataTypeHandler<NumberSequence, MetaNumberSequence>,

    getDataTypePropertyValue: (value: any) -> Deserialisable,
    getDataTypeFromPropertyValue: (value: any) -> Serialisable,

    validateAttributeName: (attributeName: string) -> boolean,
    getInstancePropertiesExtra: (instance: Instance) -> {[string]: any},
}

--// Constants

local ATTRIBUTE_NAME_ALLOWED_CHARS = {
    ".",
    "_",
    "-",
    "/"
}

--// Module
local TreeDataTypes = {}

TreeDataTypes["Axes"] = {
    Ser = function(value: Axes): MetaAxes
        local axes = value
        local axesData: {string} = {}
        if axes.X then
            table.insert(axesData, "X")
        end
        if axes.Y then
            table.insert(axesData, "Y")
        end
        if axes.Z then
            table.insert(axesData, "Z")
        end
        return {
            Axes = axesData,
        }
    end,
    Des = function(data: MetaAxes): Axes
        local axesData = data["Axes"] :: {string}
        local x = false
        local y = false
        local z = false
        for _, axis in axesData do
            if axis == "X" then
                x = true
            elseif axis == "Y" then
                y = true
            elseif axis == "Z" then
                z = true
            end
        end
        return roblox.Axes.new(x, y, z)
    end,
}

TreeDataTypes["Content"] = {
    Ser = function(value: Content): MetaContent
        local content = value
		return {
			Content = content.Uri,
		}
    end,
    Des = function(data: MetaContent): Content
        local uri = data["Content"]
        return roblox.Content.fromUri(uri)
    end,
}

TreeDataTypes["Color3"] = {
    Ser = function(value: Color3): MetaColor3
        local color = value
        return {
            Color3 = {
                color.R,
                color.G,
                color.B,
            }
        }
    end,
    Des = function(data: MetaColor3): Color3
        local colorData = data["Color3"]
        local r = colorData[1] :: number
        local g = colorData[2] :: number
        local b = colorData[3] :: number
        return roblox.Color3.new(r, g, b)
    end,
}

TreeDataTypes["ColorSequence"] = {
    Ser = function(value: ColorSequence): MetaColorSequence
        local colorSequence = value
        local keypointsData: {{
            time: number,
            color: {number},
        }} = {}
        for _, keypoint in colorSequence.Keypoints do
            table.insert(keypointsData, {
                time = keypoint.Time,
                color = {keypoint.Value.R, keypoint.Value.G, keypoint.Value.B},
            })
        end
        return {
            ColorSequence = {
                keypoints = keypointsData,
            }
        }
    end,
    Des = function(data: MetaColorSequence): ColorSequence
        local colorSequenceData = data["ColorSequence"]
        local keypointsData = colorSequenceData["keypoints"]
        local keypoints: {ColorSequenceKeypoint} = {}
        for _, keypointData in keypointsData do
            local time = keypointData["time"]
            local colorData = keypointData["color"]
            local r = colorData[1] :: number
            local g = colorData[2] :: number
            local b = colorData[3] :: number
            local value = roblox.Color3.new(r, g, b)
            table.insert(keypoints, roblox.ColorSequenceKeypoint.new(time, value))
        end
        return roblox.ColorSequence.new(keypoints)
    end,
}

TreeDataTypes["CFrame"] = {
    Ser = function(value: CFrame): MetaCFrame
        local cframe = value
        local data = {} :: {
            position: {number},
            orientation: {{number}},
        }

        local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = cframe:GetComponents()

        data.position = {x, y, z}
        data.orientation = {{R00, R01, R02}, {R10, R11, R12}, {R20, R21, R22}}

        return {
            CFrame = data
        }
    end,
    Des = function(data: MetaCFrame): CFrame
        local cframeData = data["CFrame"]
        local positionData = cframeData.position
        local orientationData = cframeData.orientation
        local x = positionData[1] :: number
        local y = positionData[2] :: number
        local z = positionData[3] :: number
        local R00 = orientationData[1][1] :: number
        local R01 = orientationData[1][2] :: number
        local R02 = orientationData[1][3] :: number
        local R10 = orientationData[2][1] :: number
        local R11 = orientationData[2][2] :: number
        local R12 = orientationData[2][3] :: number
        local R20 = orientationData[3][1] :: number
        local R21 = orientationData[3][2] :: number
        local R22 = orientationData[3][3] :: number
        return roblox.CFrame.new(
            x, y, z,
            R00, R01, R02,
            R10, R11, R12,
            R20, R21, R22
        )
    end,
}

TreeDataTypes["Font"] = {
    Ser = function(value: Font): MetaFont
        local font = value
        return {
            Font = {
                family = font.Family,
                weight = font.Weight.Name,
                style = font.Style.Name,
            }
        }
    end,
    Des = function(data: MetaFont): Font
        local fontData = data["Font"]
        local family = fontData["family"]
        local weightName = fontData["weight"]
        local styleName = fontData["style"]

        local weight = roblox.Enum.FontWeight[weightName] :: Enum.FontWeight
        local style = roblox.Enum.FontStyle[styleName] :: Enum.FontStyle

        return roblox.Font.fromId(
            tonumber(family),
            weight,
            style
        )
    end,
}

TreeDataTypes["Instance"] = {
    Ser = function(value: Instance): MetaInstance -- ref
        local instance = value
        -- Util.warn("Instance reference serialisation is not supported.")
        return {
            Instance = {
                path = Util.getInstancePath(instance),
            }
        }
    end,
    Des = function(data: MetaInstance): string
        local instanceData = data["Instance"] :: any
        local resolvePath = instanceData["path"] :: string
        return resolvePath
    end,
}

TreeDataTypes["UDim"] = {
    Ser = function(value: UDim): MetaUDim
        local udim = value
        return {
            UDim = {
                udim.Scale,
                udim.Offset,
            }
        }
    end,
    Des = function(data: MetaUDim): UDim
        local udimData = data["UDim"]
        local scale = udimData[1]
        local offset = udimData[2]
        return roblox.UDim.new(scale, offset)
    end,
}

TreeDataTypes["UDim2"] = {
    Ser = function(value: UDim2): MetaUDim2
        local udim2 = value
        return {
            UDim2 = {
                {
                    udim2.X.Scale,
                    udim2.X.Offset,
                },
                {
                    udim2.Y.Scale,
                    udim2.Y.Offset,
                }
            }
        }
    end,
    Des = function(data: MetaUDim2): UDim2
        local udim2Data = data["UDim2"]
        local xData = udim2Data[1]
        local yData = udim2Data[2]

        local xScale = xData[1]
        local xOffset = xData[2]
        local yScale = yData[1]
        local yOffset = yData[2]
        return roblox.UDim2.new(
            roblox.UDim.new(xScale, xOffset),
            roblox.UDim.new(yScale, yOffset)
        )
    end,
}

TreeDataTypes["Vector2"] = {
    Ser = function(value: Vector2): MetaVector2
        local vector = value
        return {
            Vector2 = {
                vector.X,
                vector.Y,
            }
        }
    end,
    Des = function(data: MetaVector2): Vector2
        local vectorData = data["Vector2"]
        local x = vectorData[1]
        local y = vectorData[2]
        return roblox.Vector2.new(x, y)
    end,
}

TreeDataTypes["Vector2int16"] = {
    Ser = function(value: Vector2int16): MetaVector2int16
        local vector = value
        return {
            Vector2int16 = {
                vector.X,
                vector.Y,
            }
        }
    end,
    Des = function(data: MetaVector2int16): Vector2int16
        local vectorData = data["Vector2int16"]
        local x = vectorData[1]
        local y = vectorData[2]
        return roblox.Vector2int16.new(x, y)
    end,
}

TreeDataTypes["Vector3"] = {
    Ser = function(value: Vector3): MetaVector3
        local vector = value
        return {
            Vector3 = {
                vector.X,
                vector.Y,
                vector.Z,
            }
        }
    end,
    Des = function(data: MetaVector3): Vector3
        local vectorData = data["Vector3"]
        local x = vectorData[1]
        local y = vectorData[2]
        local z = vectorData[3]
        return roblox.Vector3.new(x, y, z)
    end,
}

TreeDataTypes["Vector3int16"] = {
    Ser = function(value: Vector3int16): any
        local vector = value
        return {
            Vector3int16 = {
                vector.X,
                vector.Y,
                vector.Z,
            }
        }
    end,
    Des = function(data: MetaVector3int16): Vector3int16
        local vectorData = data["Vector3int16"] :: {number}
        local x = vectorData[1]
        local y = vectorData[2]
        local z = vectorData[3]
        return roblox.Vector3int16.new(x, y, z)
    end,
}

TreeDataTypes["NumberRange"] = {
    Ser = function(value: NumberRange): MetaNumberRange
        local numberRange = value
        return {
            NumberRange = {
                numberRange.Min,
                numberRange.Max,
            }
        }
    end,
    Des = function(data: MetaNumberRange): NumberRange
        local numberRangeData = data["NumberRange"]
        local min = numberRangeData[1]
        local max = numberRangeData[2]
        return roblox.NumberRange.new(min, max)
    end,
}

TreeDataTypes["NumberSequence"] = {
    Ser = function(value: NumberSequence): MetaNumberSequence
        local numberSequence = value
        local keypointsData: {{number}} = {}
        for _, keypoint in numberSequence.Keypoints do
            table.insert(keypointsData, {
                keypoint.Time,
                keypoint.Value,
                keypoint.Envelope,
            })
        end
        return {
            NumberSequence = {
                keypoints = keypointsData,
            }
        }
    end,
    Des = function(data: MetaNumberSequence): NumberSequence
        local numberSequenceData = data["NumberSequence"]
        local keypointsData = numberSequenceData["keypoints"]
        local keypoints: {NumberSequenceKeypoint} = {}
        for _, keypointData in keypointsData do
            local time = keypointData[1]
            local value = keypointData[2]
            local envelope = keypointData[3]
            table.insert(keypoints, roblox.NumberSequenceKeypoint.new(time, value, envelope))
        end
        return roblox.NumberSequence.new(keypoints)
    end,
}

function TreeDataTypes.getDataTypePropertyValue(
	value: any
): Deserialisable
	local dataType = typeof(value)
	if TreeDataTypes[dataType] then
		local serialiser = TreeDataTypes[dataType].Ser
		return serialiser(value)
	else
		Util.warn("No serialiser for data type:", dataType)
		return tostring(value)
	end
end

function TreeDataTypes.getDataTypeFromPropertyValue(
	value: any
): Serialisable
	local dataType = ""
	for typeName, _ in value do
		dataType = typeName
		break
	end

	if TreeDataTypes[dataType] then
		local deserialiser = TreeDataTypes[dataType].Des
		return deserialiser(value)
	else
		Util.warn("No deserialiser for data type:", dataType)
		return tostring(value)
	end
end

function TreeDataTypes.validateAttributeName(attributeName: string): boolean
    if Util.stringStartsWith(attributeName, "RBX") then
        Util.warn("Attribute names cannot start with 'RBX'.\nOffending attribute: " .. attributeName)
        return false
    end

    if #attributeName == 0 then
        Util.warn("Attribute names cannot be empty.")
        return false
    end

    if #attributeName > 100 then
        Util.warn("Attribute names cannot be longer than 100 characters.\nOffending attribute: " .. attributeName)
        return false
    end

    local function charIsValid(char: string): boolean
        if Util.stringIsAlphanumeric(char) then
            return true
        end

        if table.find(ATTRIBUTE_NAME_ALLOWED_CHARS, char) then
            return true
        end

        return false
    end

    local attributeChars = Util.stringChars(attributeName)
    if not Util.matchesFilter(attributeChars, charIsValid) then
        Util.warn("Attribute names can only contain alphanumeric characters, or any of these characters: " .. Util.stringCombine(ATTRIBUTE_NAME_ALLOWED_CHARS, " ") .. ". \nOffending attribute: " .. attributeName)
        return false
    end

    return true
end

local MANUAL_PROPERTIES = {
    --/ ClassName: {PropName: Default}
}

MANUAL_PROPERTIES["BasePart"] = {
    Anchored = false,
    AudioCanCollide = true,
    CFrame = roblox.CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
    CanCollide = true,
    CanQuery = true,
    CanTouch = true,
    CastShadow = true,
    CollisionGroup = "Default",
    Color = roblox.Color3.new(0.6392157, 0.63529414, 0.64705884),
    EnableFluidForces = true,
    Locked = false,
    Massless = false,
    Material = "Plastic",
    MaterialVariant = "",
    PivotOffset = roblox.CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
    Reflectance = 0,
    RootPriority = 0,
    Size = roblox.Vector3.new(4, 1.2, 2),
    Transparency = 0,
}

MANUAL_PROPERTIES["Tool"] = {
    CanBeDropped = true,
    Enabled = true,
    Grip = roblox.CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
    ManualActivationOnly = false,
    RequiresHandle = true,
    ToolTip = "",
}

function TreeDataTypes.getInstancePropertiesExtra(instance: Instance): {[string]: any}
    local properties: {[string]: any} = {}

    for manualPropertyClass, manualProperties in MANUAL_PROPERTIES do
        if instance:IsA(manualPropertyClass) then
            for propName, propDefaultValue in manualProperties do
                local success, value = pcall(function()
                    return instance[propName]
                end)
                if success then
                    if value ~= propDefaultValue then 
                        if type(value) == "userdata" then
                            local dataType = typeof(value)
                            if dataType == "EnumItem" then
                                properties[propName] = value.Name
                            else
                                properties[propName] = TreeDataTypes.getDataTypePropertyValue(value)
                            end
                        else
                            properties[propName] = value
                        end
                    end
				end
            end
        end
    end

    return properties
end

return TreeDataTypes :: TreeDataTypesT