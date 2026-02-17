local Rain = require(script:WaitForChild("RainModule"))

local module = {}

local configured = false
local pendingStopTask = nil
local stopRequestId = 0

local DEFAULTS = {
	Color = Color3.fromRGB(255, 255, 255),
	Direction = Vector3.new(0, -1, 0),
	Transparency = 0,
	SpeedRatio = 1,
	IntensityRatio = 1,
	LightInfluence = 0.9,
	LightEmission = 0.05,
	Volume = 0.35,
	SoundId = "",
	StraightTexture = "",
	TopDownTexture = "",
	SplashTexture = "",
	TransparencyThreshold = 0.95,
	TransparencyConstraint = false,
	CanCollideConstraint = false,
}

local function readValue(name, defaultValue)
	local valueObject = script:FindFirstChild(name)
	if valueObject == nil then
		return defaultValue
	end

	local ok, value = pcall(function()
		return valueObject.Value
	end)
	if not ok or value == nil then
		return defaultValue
	end

	return value
end

local function readColor()
	local value = readValue("Color", DEFAULTS.Color)
	if typeof(value) == "Color3" then
		return value
	end
	if typeof(value) == "Vector3" then
		return Color3.fromRGB(value.X, value.Y, value.Z)
	end

	return DEFAULTS.Color
end

local function applyRainSettings()
	Rain:SetColor(readColor())
	Rain:SetDirection(readValue("Direction", DEFAULTS.Direction))

	Rain:SetTransparency(readValue("Transparency", DEFAULTS.Transparency))
	Rain:SetSpeedRatio(readValue("SpeedRatio", DEFAULTS.SpeedRatio))
	Rain:SetIntensityRatio(readValue("IntensityRatio", DEFAULTS.IntensityRatio))
	Rain:SetLightInfluence(readValue("LightInfluence", DEFAULTS.LightInfluence))
	Rain:SetLightEmission(readValue("LightEmission", DEFAULTS.LightEmission))
	Rain:SetVolume(readValue("Volume", DEFAULTS.Volume))

	local soundId = readValue("SoundId", DEFAULTS.SoundId)
	if typeof(soundId) == "string" and soundId ~= "" then
		Rain:SetSoundId(soundId)
	end

	local straightTexture = readValue("StraightTexture", DEFAULTS.StraightTexture)
	if typeof(straightTexture) == "string" and straightTexture ~= "" then
		Rain:SetStraightTexture(straightTexture)
	end

	local topDownTexture = readValue("TopDownTexture", DEFAULTS.TopDownTexture)
	if typeof(topDownTexture) == "string" and topDownTexture ~= "" then
		Rain:SetTopDownTexture(topDownTexture)
	end

	local splashTexture = readValue("SplashTexture", DEFAULTS.SplashTexture)
	if typeof(splashTexture) == "string" and splashTexture ~= "" then
		Rain:SetSplashTexture(splashTexture)
	end

	local threshold = readValue("TransparencyThreshold", DEFAULTS.TransparencyThreshold)
	local useTransparencyConstraint = readValue("TransparencyConstraint", DEFAULTS.TransparencyConstraint) == true
	local useCanCollideConstraint = readValue("CanCollideConstraint", DEFAULTS.CanCollideConstraint) == true

	if useTransparencyConstraint and useCanCollideConstraint then
		Rain:SetCollisionMode(Rain.CollisionMode.Function, function(part)
			return part.Transparency <= threshold and part.CanCollide
		end)
	elseif useTransparencyConstraint then
		Rain:SetCollisionMode(Rain.CollisionMode.Function, function(part)
			return part.Transparency <= threshold
		end)
	elseif useCanCollideConstraint then
		Rain:SetCollisionMode(Rain.CollisionMode.Function, function(part)
			return part.CanCollide
		end)
	else
		Rain:SetCollisionMode(Rain.CollisionMode.None)
	end
end

local function ensureConfigured()
	if configured then
		return
	end

	applyRainSettings()
	configured = true
end

local function getTransitionTime(options)
	if type(options) ~= "table" then
		return 0
	end

	local transitionTime = tonumber(options.transitionTime)
	if not transitionTime or transitionTime <= 0 then
		return 0
	end

	return transitionTime
end

local function cancelPendingStop()
	stopRequestId += 1
	if pendingStopTask then
		task.cancel(pendingStopTask)
		pendingStopTask = nil
	end
end

function module:Start(_options)
	if self == nil then
		-- Called by generic loader without module context; ignore.
		return
	end

	cancelPendingStop()
	ensureConfigured()
	Rain:Enable()
end

function module:Stop(options)
	if self == nil then
		return
	end

	cancelPendingStop()

	local delaySeconds = getTransitionTime(options)
	if delaySeconds <= 0 then
		Rain:Disable()
		return
	end

	local requestId = stopRequestId
	pendingStopTask = task.delay(delaySeconds, function()
		if requestId ~= stopRequestId then
			return
		end

		pendingStopTask = nil
		Rain:Disable()
	end)
end

return module
