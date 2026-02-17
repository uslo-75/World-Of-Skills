local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ZonePresets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Zone"):WaitForChild("ZonePresets"))
local DynamicAmbience = {
	Apply = function() end,
}

if RunService:IsClient() then
	DynamicAmbience = require(ReplicatedStorage:WaitForChild("LocalHandler"):WaitForChild("Misc"):WaitForChild("DynamicAmbience"))
end

local ZoneEnvironmentController = {}
ZoneEnvironmentController.__index = ZoneEnvironmentController

local LIGHTING_PROPS = {
	"Ambient",
	"OutdoorAmbient",
	"Brightness",
	"ColorShift_Bottom",
	"ColorShift_Top",
	"FogColor",
	"FogStart",
	"FogEnd",
	"ExposureCompensation",
}

local ATMOSPHERE_PROPS = {
	"Density",
	"Offset",
	"Color",
	"Decay",
	"Glare",
	"Haze",
}

local COLOR_CORRECTION_PROPS = {
	"TintColor",
	"Saturation",
	"Contrast",
	"Brightness",
}

local DYNAMIC_VFX_KEYS = { "Snow", "Rain", "Fog", "Sand", "Wind", "Wind_Snow" }

local function captureProperties(instance, properties)
	if not instance then
		return nil
	end

	local data = {}
	for _, propertyName in ipairs(properties) do
		data[propertyName] = instance[propertyName]
	end

	return data
end

local function buildGoalValues(propertyList, baseline, presetValues)
	local goal = {}
	local hasValues = false

	for _, propertyName in ipairs(propertyList) do
		local value = nil
		if type(presetValues) == "table" and presetValues[propertyName] ~= nil then
			value = presetValues[propertyName]
		elseif type(baseline) == "table" and baseline[propertyName] ~= nil then
			value = baseline[propertyName]
		end

		if value ~= nil then
			goal[propertyName] = value
			hasValues = true
		end
	end

	if not hasValues then
		return nil
	end

	return goal
end

local function tween(instance, duration, goal)
	if not goal or not next(goal) then
		return nil
	end

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tw = TweenService:Create(instance, tweenInfo, goal)
	tw:Play()
	return tw
end

local function normalizeMusicId(rawId)
	if rawId == nil then
		return nil
	end

	if typeof(rawId) == "number" then
		return "rbxassetid://" .. tostring(math.floor(rawId))
	end

	if typeof(rawId) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(rawId, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end

	if string.match(trimmed, "^rbxassetid://%d+$") then
		return trimmed
	end

	local onlyDigits = string.match(trimmed, "^(%d+)$")
	if onlyDigits then
		return "rbxassetid://" .. onlyDigits
	end

	return trimmed
end

local function getOrCreateSoundChannel(parent, name)
	local sound = parent:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		return sound
	end

	sound = Instance.new("Sound")
	sound.Name = name
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = parent

	return sound
end

local function resolveDynamicVFX(preset, zoneInfo)
	local resolved = {}
	local presetConfig = (type(preset.DynamicVFX) == "table" and preset.DynamicVFX) or {}
	local zoneConfig = (zoneInfo and type(zoneInfo.dynamicVFX) == "table" and zoneInfo.dynamicVFX) or {}

	for _, key in ipairs(DYNAMIC_VFX_KEYS) do
		local zoneValue = zoneConfig[key]
		local presetValue = presetConfig[key]
		local fallbackTopLevel = preset[key]

		if typeof(zoneValue) == "boolean" then
			resolved[key] = zoneValue
		elseif typeof(presetValue) == "boolean" then
			resolved[key] = presetValue
		else
			resolved[key] = fallbackTopLevel == true
		end
	end

	return resolved
end

function ZoneEnvironmentController.new()
	local self = setmetatable({}, ZoneEnvironmentController)

	self._lightingTweens = {}
	self._musicTweens = {}

	local baseAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local baseColorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")

	self._baseline = {
		Lighting = captureProperties(Lighting, LIGHTING_PROPS),
		Atmosphere = captureProperties(baseAtmosphere, ATMOSPHERE_PROPS),
		ColorCorrection = captureProperties(baseColorCorrection, COLOR_CORRECTION_PROPS),
	}

	local musicFolder = SoundService:FindFirstChild("ZoneMusicChannels")
	if not musicFolder then
		musicFolder = Instance.new("Folder")
		musicFolder.Name = "ZoneMusicChannels"
		musicFolder.Parent = SoundService
	end

	self._musicA = getOrCreateSoundChannel(musicFolder, "ChannelA")
	self._musicB = getOrCreateSoundChannel(musicFolder, "ChannelB")
	self._activeChannel = nil
	self._activeMusicId = nil

	return self
end

function ZoneEnvironmentController:_cancelTweens(list)
	for _, tw in ipairs(list) do
		if tw then
			tw:Cancel()
		end
	end
	table.clear(list)
end

function ZoneEnvironmentController:_pushTween(list, tw)
	if tw then
		table.insert(list, tw)
	end
end

function ZoneEnvironmentController:_getOrCreateAtmosphere()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		return atmosphere
	end

	atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "ZoneAtmosphere"
	atmosphere.Parent = Lighting
	return atmosphere
end

function ZoneEnvironmentController:_getOrCreateColorCorrection()
	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if colorCorrection then
		return colorCorrection
	end

	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "ZoneColorCorrection"
	colorCorrection.Parent = Lighting
	return colorCorrection
end

function ZoneEnvironmentController:_applyLighting(preset, duration)
	self:_cancelTweens(self._lightingTweens)

	local lightingGoal = buildGoalValues(LIGHTING_PROPS, self._baseline.Lighting, preset.Lighting)
	self:_pushTween(self._lightingTweens, tween(Lighting, duration, lightingGoal))

	local shouldHandleAtmosphere = (type(preset.Atmosphere) == "table" and next(preset.Atmosphere) ~= nil)
		or self._baseline.Atmosphere ~= nil
	if shouldHandleAtmosphere then
		local atmosphere = self:_getOrCreateAtmosphere()
		local atmosphereGoal = buildGoalValues(ATMOSPHERE_PROPS, self._baseline.Atmosphere, preset.Atmosphere)
		self:_pushTween(self._lightingTweens, tween(atmosphere, duration, atmosphereGoal))
	end

	local shouldHandleColorCorrection = (type(preset.ColorCorrection) == "table" and next(preset.ColorCorrection) ~= nil)
		or self._baseline.ColorCorrection ~= nil
	if shouldHandleColorCorrection then
		local colorCorrection = self:_getOrCreateColorCorrection()
		local colorCorrectionGoal =
			buildGoalValues(COLOR_CORRECTION_PROPS, self._baseline.ColorCorrection, preset.ColorCorrection)
		self:_pushTween(self._lightingTweens, tween(colorCorrection, duration, colorCorrectionGoal))
	end
end

function ZoneEnvironmentController:_getNextChannel()
	if self._activeChannel == self._musicA then
		return self._musicB
	end

	return self._musicA
end

function ZoneEnvironmentController:_fadeOutAndStop(sound, duration)
	self:_pushTween(self._musicTweens, tween(sound, duration, { Volume = 0 }))
	task.delay(duration, function()
		if sound.Volume <= 0.001 then
			sound:Stop()
		end
	end)
end

function ZoneEnvironmentController:_applyMusic(musicId, musicVolume, duration)
	self:_cancelTweens(self._musicTweens)

	local normalizedMusicId = normalizeMusicId(musicId)
	local targetVolume = tonumber(musicVolume) or ZonePresets.Default.MusicVolume or 0.25

	if not normalizedMusicId then
		self:_fadeOutAndStop(self._musicA, duration)
		self:_fadeOutAndStop(self._musicB, duration)
		self._activeChannel = nil
		self._activeMusicId = nil
		return
	end

	if self._activeChannel and self._activeMusicId == normalizedMusicId then
		if not self._activeChannel.IsPlaying then
			self._activeChannel:Play()
		end
		self:_pushTween(self._musicTweens, tween(self._activeChannel, duration, { Volume = targetVolume }))

		local other = (self._activeChannel == self._musicA) and self._musicB or self._musicA
		if other.IsPlaying then
			self:_fadeOutAndStop(other, duration)
		end
		return
	end

	local incoming = self:_getNextChannel()
	incoming.SoundId = normalizedMusicId
	incoming.TimePosition = 0
	incoming.Volume = 0
	incoming:Play()

	self:_pushTween(self._musicTweens, tween(incoming, duration, { Volume = targetVolume }))

	if self._activeChannel and self._activeChannel ~= incoming and self._activeChannel.IsPlaying then
		self:_fadeOutAndStop(self._activeChannel, duration)
	end

	self._activeChannel = incoming
	self._activeMusicId = normalizedMusicId
end

function ZoneEnvironmentController:ApplyZone(zoneInfo)
	local presetName = nil
	if zoneInfo then
		presetName = zoneInfo.lightingPreset or zoneInfo.id
	end

	local preset = ZonePresets.Get(presetName)
	local duration = (zoneInfo and zoneInfo.transitionTime) or preset.TransitionTime or ZonePresets.Default.TransitionTime or 1.25

	self:_applyLighting(preset, duration)

	local musicId = (zoneInfo and zoneInfo.musicId) or preset.MusicId
	local musicVolume = (zoneInfo and zoneInfo.musicVolume) or preset.MusicVolume
	self:_applyMusic(musicId, musicVolume, duration)

	local dynamicVFXConfig = resolveDynamicVFX(preset, zoneInfo)
	DynamicAmbience.Apply(dynamicVFXConfig, {
		transitionTime = duration,
	})
end

return ZoneEnvironmentController
