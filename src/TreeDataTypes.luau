--!nonstrict
--// TreeDataTypes
--// Author: okzyrox
--/ Date: 2025/12/26

--// Modules
local roblox = require("@lune/roblox")

local Util = require("./Util")

--// Types

export type DataTypeHandler<T> = {
    Ser: (value: any) -> any,
    Des: (data: any) -> T,
}

export type TreeDataTypesT = {
    ["Axes"]: DataTypeHandler<Axes>,
    ["Content"]: DataTypeHandler<Content>,
    ["Color3"]: DataTypeHandler<Color3>,
    ["CFrame"]: DataTypeHandler<CFrame>,
    ["UDim"]: DataTypeHandler<UDim>,
    ["UDim2"]: DataTypeHandler<UDim2>,
    ["Vector2"]: DataTypeHandler<Vector2>,
    ["Vector2int16"]: DataTypeHandler<Vector2int16>,
    ["Vector3"]: DataTypeHandler<Vector3>,
    ["Vector3int16"]: DataTypeHandler<Vector3int16>,
    ["NumberRange"]: DataTypeHandler<NumberRange>,
    ["NumberSequence"]: DataTypeHandler<NumberSequence>,

    validateAttributeName: (attributeName: string) -> boolean,
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
    Ser = function(value: any): any
        local axes = value :: Axes
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
    Des = function(data: any): Axes
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
    Ser = function(value: any): any
        local content = value :: Content
		return {
			Content = content.Uri,
		}
    end,
    Des = function(data: any): Content
        local uri = data["Content"] :: string
        return roblox.Content.fromUri(uri)
    end,
}

TreeDataTypes["Color3"] = {
    Ser = function(value: any): any
        local color = value :: Color3
        return {
            Color3 = {
                color.R,
                color.G,
                color.B,
            }
        }
    end,
    Des = function(data: any): Color3
        local colorData = data["Color3"] :: {number}
        local r = colorData[1] :: number
        local g = colorData[2] :: number
        local b = colorData[3] :: number
        return roblox.Color3.new(r, g, b)
    end,
}

TreeDataTypes["ColorSequence"] = {
    Ser = function(value: any): any
        local colorSequence = value :: ColorSequence
        local keypointsData: {any} = {}
        for _, keypoint in colorSequence.Keypoints do
            table.insert(keypointsData, {
                time = keypoint.Time,
                color = {keypoint.Value.R, keypoint.Value.G, keypoint.Value.B},
            })
        end
        return {
            keypoints = keypointsData,
        }
    end,
    Des = function(data: any): ColorSequence
        local keypointsData = data["keypoints"] :: {any}
        local keypoints: {ColorSequenceKeypoint} = {}
        for _, keypointData in keypointsData do
            local time = keypointData["time"] :: number
            local valueData = keypointData["color"] :: {number}
            local r = valueData[1] :: number
            local g = valueData[2] :: number
            local b = valueData[3] :: number
            local value = roblox.Color3.new(r, g, b)
            table.insert(keypoints, roblox.ColorSequenceKeypoint.new(time, value))
        end
        return roblox.ColorSequence.new(keypoints)
    end,
}

TreeDataTypes["CFrame"] = {
    Ser = function(value: any): any
        local cframe = value :: CFrame
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
    Des = function(data: any): CFrame
        local cframeData = data["CFrame"] :: {number}
        local positionData = cframeData.position :: {number}
        local orientationData = cframeData.orientation :: {{number}}
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
    Ser = function(value: any): any
        local font = value :: Font
        return {
            Font = {
                family = font.Family,
                weight = font.Weight.Name,
                style = font.Style.Name,
            }
        }
    end,
    Des = function(data: any): Font
        local fontData = data["Font"] :: any
        local family = fontData["family"] :: string
        local weightName = fontData["weight"] :: string
        local styleName = fontData["style"] :: string

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
    Ser = function(value: any): any
        local instance = value :: Instance
        Util.warn("Instance reference serialisation is not supported.")
        return {
            InstanceReference = {
                className = instance.ClassName,
                name = instance.Name,
                path = Util.getInstancePath(instance),
            }
        }
    end,
    Des = function(data: any): Instance
        local instanceData = data["InstanceReference"] :: any
        local className = instanceData["className"] :: string
        local instance = roblox.Instance.new(className)
        instance.Name = instanceData["name"] :: string
        return instance
    end,
}

TreeDataTypes["UDim"] = {
    Ser = function(value: any): any
        local udim = value :: UDim
        return {
            UDim = {
                udim.Scale,
                udim.Offset,
            }
        }
    end,
    Des = function(data: any): UDim
        local udimData = data["UDim"] :: {number}
        local scale = udimData[1] :: number
        local offset = udimData[2] :: number
        return roblox.UDim.new(scale, offset)
    end,
}

TreeDataTypes["UDim2"] = {
    Ser = function(value: any): any
        local udim2 = value :: UDim2
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
    Des = function(data: any): UDim2
        local udim2Data = data["UDim2"] :: {{number}}
        local xData = udim2Data[1] :: {number}
        local yData = udim2Data[2] :: {number}
        local xScale = xData[1] :: number
        local xOffset = xData[2] :: number
        local yScale = yData[1] :: number
        local yOffset = yData[2] :: number
        return roblox.UDim2.new(
            roblox.UDim.new(xScale, xOffset),
            roblox.UDim.new(yScale, yOffset)
        )
    end,
}

TreeDataTypes["Vector2"] = {
    Ser = function(value: any): any
        local vector = value :: Vector2
        return {
            Vector2 = {
                vector.X,
                vector.Y,
            }
        }
    end,
    Des = function(data: any): Vector2
        local vectorData = data["Vector2"] :: {number}
        local x = vectorData[1] :: number
        local y = vectorData[2] :: number
        return roblox.Vector2.new(x, y)
    end,
}

TreeDataTypes["Vector2int16"] = {
    Ser = function(value: any): any
        local vector = value :: Vector2int16
        return {
            Vector2int16 = {
                vector.X,
                vector.Y,
            }
        }
    end,
    Des = function(data: any): Vector2int16
        local vectorData = data["Vector2int16"] :: {number}
        local x = vectorData[1] :: number
        local y = vectorData[2] :: number
        return roblox.Vector2int16.new(x, y)
    end,
}

TreeDataTypes["Vector3"] = {
    Ser = function(value: any): any
        local vector = value :: Vector3
        return {
            Vector3 = {
                vector.X,
                vector.Y,
                vector.Z,
            }
        }
    end,
    Des = function(data: any): Vector3
        local vectorData = data["Vector3"] :: {number}
        local x = vectorData[1] :: number
        local y = vectorData[2] :: number
        local z = vectorData[3] :: number
        return roblox.Vector3.new(x, y, z)
    end,
}

TreeDataTypes["Vector3int16"] = {
    Ser = function(value: any): any
        local vector = value :: Vector3int16
        return {
            Vector3int16 = {
                vector.X,
                vector.Y,
                vector.Z,
            }
        }
    end,
    Des = function(data: any): Vector3int16
        local vectorData = data["Vector3int16"] :: {number}
        local x = vectorData[1] :: number
        local y = vectorData[2] :: number
        local z = vectorData[3] :: number
        return roblox.Vector3int16.new(x, y, z)
    end,
}

TreeDataTypes["NumberRange"] = {
    Ser = function(value: any): any
        local numberRange = value :: NumberRange
        return {
            numberRange.Min,
            numberRange.Max,
        }
    end,
    Des = function(data: any): NumberRange
        local min = data[1] :: number
        local max = data[2] :: number
        return roblox.NumberRange.new(min, max)
    end,
}

TreeDataTypes["NumberSequence"] = {
    Ser = function(value: any): any
        local numberSequence = value :: NumberSequence
        local keypointsData: {any} = {}
        for _, keypoint in numberSequence.Keypoints do
            table.insert(keypointsData, {
                keypoint.Time,
                keypoint.Value,
                keypoint.Envelope,
            })
        end
        return {
            keypoints = keypointsData,
        }
    end,
    Des = function(data: any): NumberSequence
        local keypointsData = data["keypoints"] :: {any}
        local keypoints: {NumberSequenceKeypoint} = {}
        for _, keypointData in keypointsData do
            local time = keypointData[1] :: number
            local value = keypointData[2] :: number
            local envelope = keypointData[3] :: number
            table.insert(keypoints, roblox.NumberSequenceKeypoint.new(time, value, envelope))
        end
        return roblox.NumberSequence.new(keypoints)
    end,
}

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

return TreeDataTypes :: TreeDataTypesT