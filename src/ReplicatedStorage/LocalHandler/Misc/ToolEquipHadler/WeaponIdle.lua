local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponIdle = {}
WeaponIdle.__index = WeaponIdle

local function getCombatFolder(toolName: string): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local animation = assets and assets:FindFirstChild("animation")
	local combat = animation and animation:FindFirstChild("combat")
	local folder = combat and combat:FindFirstChild(toolName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function findIdleAnimation(toolName: string): Animation?
	local folder = getCombatFolder(toolName)
	if not folder then
		return nil
	end

	local candidates = { "idle", "Idle" }
	for _, name in ipairs(candidates) do
		local anim = folder:FindFirstChild(name)
		if anim and anim:IsA("Animation") then
			return anim
		end
	end

	return nil
end

function WeaponIdle.new(deps)
	local self = setmetatable({}, WeaponIdle)

	self.Config = deps.Config
	self.AnimationHandler = deps.AnimationHandler
	self._character = nil
	self._track = nil
	self._trackStoppedConn = nil

	return self
end

function WeaponIdle:isPlaying(): boolean
	local track = self._track
	if track then
		local ok, playing = pcall(function()
			return track.IsPlaying
		end)
		if ok and playing then
			return true
		end
	end

	local char = self._character
	if not char then
		return false
	end

	local anims = self.AnimationHandler.GetAnims(char, self.Config.WeaponIdleAnimType)
	for _, animData in pairs(anims) do
		local animTrack = animData and animData.Track
		if animTrack then
			local ok, playing = pcall(function()
				return animTrack.IsPlaying
			end)
			if ok and playing then
				self._track = animTrack
				return true
			end
		end
	end

	return false
end

function WeaponIdle:stop(character: Model?)
	if self._trackStoppedConn then
		self._trackStoppedConn:Disconnect()
		self._trackStoppedConn = nil
	end
	self._track = nil
	self._character = character or self._character

	if not character then
		return
	end

	self.AnimationHandler.StopAnims(character, self.Config.WeaponIdleAnimType)
end

function WeaponIdle:play(character: Model?, toolName: string)
	if not character or toolName == "" then
		return false
	end

	local anim = findIdleAnimation(toolName)
	if not anim then
		return false
	end

	self:stop(character)

	local track = self.AnimationHandler.LoadAnim(character, self.Config.WeaponIdleAnimType, anim.AnimationId, nil, {
		replaceType = true,
		priority = self.Config.WeaponIdlePriority,
		fadeTime = self.Config.WeaponIdleFadeTime,
		looped = true,
	})
	if not track then
		return false
	end

	track.Name = self.Config.WeaponIdleTrackName
	self._character = character
	self._track = track
	self._trackStoppedConn = track.Stopped:Connect(function()
		if self._track == track then
			self._track = nil
		end
	end)
	return true
end

return WeaponIdle
