local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponAnim = {}
WeaponAnim.__index = WeaponAnim

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

local function findAnimation(toolName: string, animName: string): Animation?
	local folder = getCombatFolder(toolName)
	if not folder then
		return nil
	end

	local anim = folder:FindFirstChild(animName)
	if anim and anim:IsA("Animation") then
		return anim
	end

	return nil
end

function WeaponAnim.new(deps)
	local self = setmetatable({}, WeaponAnim)

	self.Config = deps.Config
	self.AnimationHandler = deps.AnimationHandler

	return self
end

function WeaponAnim:stop(character: Model?)
	if not character then
		return
	end
	self.AnimationHandler.StopAnims(character, self.Config.WeaponEquipAnimType)
	self.AnimationHandler.StopAnims(character, self.Config.WeaponUnequipAnimType)
end

local function playTransition(self, character: Model?, toolName: string, animName: string, animType: string): AnimationTrack?
	if not character or toolName == "" then
		return nil
	end

	local anim = findAnimation(toolName, animName)
	if not anim then
		return nil
	end

	local track = self.AnimationHandler.LoadAnim(character, animType, anim.AnimationId, nil, {
		replaceType = true,
		priority = self.Config.WeaponTransitionPriority,
		fadeTime = self.Config.WeaponTransitionFadeTime,
	})
	if not track then
		return nil
	end

	track.Name = animName
	return track
end

function WeaponAnim:playEquip(character: Model?, toolName: string)
	return playTransition(self, character, toolName, self.Config.WeaponEquipAnimationName, self.Config.WeaponEquipAnimType)
end

function WeaponAnim:playUnequip(character: Model?, toolName: string)
	return playTransition(
		self,
		character,
		toolName,
		self.Config.WeaponUnequipAnimationName,
		self.Config.WeaponUnequipAnimType
	)
end

return WeaponAnim
