local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ZoneUIController = {}
ZoneUIController.__index = ZoneUIController

local FADE_IN_TIME = 0.4
local HOLD_TIME = 2.6
local FADE_OUT_TIME = 0.55
local ENTRY_SFX_ID = "rbxassetid://5302239409"
local ENTRY_SFX_VOLUME = 0.45

local function getInterfaceGui(playerGui)
	local main = playerGui:FindFirstChild("Main")
	local fromMain = main and main:FindFirstChild("InterfaceGui")
	if fromMain and fromMain:IsA("ScreenGui") then
		return fromMain
	end

	local direct = playerGui:FindFirstChild("InterfaceGui")
	if direct and direct:IsA("ScreenGui") then
		return direct
	end

	local deep = playerGui:FindFirstChild("InterfaceGui", true)
	if deep and deep:IsA("ScreenGui") then
		return deep
	end

	return nil
end

local function getZoneUI()
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil, nil, nil, nil
	end

	local interfaceGui = getInterfaceGui(playerGui)
	local zoneFrame = interfaceGui and interfaceGui:FindFirstChild("ZoneFrame", true)
	local label = zoneFrame and zoneFrame:FindFirstChild("Zone_Name")
	local image = zoneFrame and zoneFrame:FindFirstChild("ImageLabel")

	if not zoneFrame or not label then
		return nil, nil, nil, nil
	end

	return zoneFrame, label, image, interfaceGui
end

local function ensureVisible(zoneFrame, interfaceGui)
	if interfaceGui then
		interfaceGui.Enabled = true
	end

	local current = zoneFrame
	while current do
		if current:IsA("GuiObject") then
			current.Visible = true
		end

		current = current.Parent
		if not current or current:IsA("PlayerGui") then
			break
		end
	end
end

local function tween(instance, duration, goal)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tw = TweenService:Create(instance, tweenInfo, goal)
	tw:Play()
	return tw
end

function ZoneUIController.new()
	local self = setmetatable({}, ZoneUIController)
	self._token = 0
	self._entrySfx = nil
	self:_setHiddenState()
	return self
end

function ZoneUIController:_playEntrySfx()
	if not self._entrySfx or not self._entrySfx.Parent then
		local sound = Instance.new("Sound")
		sound.Name = "ZoneTransitionSFX"
		sound.SoundId = ENTRY_SFX_ID
		sound.Volume = ENTRY_SFX_VOLUME
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.Parent = SoundService
		self._entrySfx = sound
	end

	self._entrySfx.TimePosition = 0
	self._entrySfx:Play()
end

function ZoneUIController:_setHiddenState()
	local zoneFrame, label, image = getZoneUI()
	if zoneFrame then
		zoneFrame.Visible = false
	end

	if not label then
		return
	end

	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	if image then
		image.ImageTransparency = 1
	end
end

function ZoneUIController:Reset()
	self._token += 1
	self:_setHiddenState()
end

function ZoneUIController:ShowZoneName(zoneName)
	local zoneFrame, label, image, interfaceGui = getZoneUI()
	if not label then
		return
	end

	ensureVisible(zoneFrame, interfaceGui)
	zoneFrame.Visible = true
	self:_playEntrySfx()

	self._token += 1
	local token = self._token

	label.Text = zoneName
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	if image then
		image.ImageTransparency = 1
	end

	tween(label, FADE_IN_TIME, {
		TextTransparency = 0,
		TextStrokeTransparency = 0,
	})

	if image then
		tween(image, FADE_IN_TIME, {
			ImageTransparency = 0,
		})
	end

	task.delay(FADE_IN_TIME + HOLD_TIME, function()
		if self._token ~= token then
			return
		end

		tween(label, FADE_OUT_TIME, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})

		if image then
			tween(image, FADE_OUT_TIME, {
				ImageTransparency = 1,
			})
		end

		task.delay(FADE_OUT_TIME, function()
			if self._token ~= token then
				return
			end
			if zoneFrame and zoneFrame.Parent then
				zoneFrame.Visible = false
			end
		end)
	end)
end

return ZoneUIController
