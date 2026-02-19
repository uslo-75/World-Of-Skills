local CharacterUtil = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CharacterUtil"))
local InstanceUtil = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("InstanceUtil"))
local AssetResolver = require(script.Parent:WaitForChild("AssetResolver"))

local module = {}

local function resolveCharacter(candidate: any): Model?
	if typeof(candidate) == "Instance" and candidate:IsA("Model") then
		return candidate
	end

	return CharacterUtil.ResolveCharacter(candidate)
end

local function resolveIndicatorEffectName(rawIndicator: any): string
	if typeof(rawIndicator) ~= "string" then
		return "RedIndicator"
	end

	local key = string.lower(rawIndicator)
	if key == "red" or key == "redindicator" or key == "red_indication" or key == "redindication" then
		return "RedIndicator"
	end
	if key == "yellow" or key == "yellowindicator" or key == "yellow_indication" or key == "yellowindication" then
		return "YellowIndicator"
	end
	if key == "blue" or key == "blueindicator" or key == "blue_indication" or key == "blueindication" then
		return "BlueIndicator"
	end

	return "RedIndicator"
end

function module.PlayWeaponSpark(replicatedStorage: ReplicatedStorage, paramsOrCharacter: any, effectName: string): boolean
	local character = resolveCharacter(paramsOrCharacter)
	if not character then
		return false
	end

	local swordPart = CharacterUtil.ResolveSwordPart(character)
	if not swordPart then
		return false
	end

	local template = AssetResolver.ResolveHitAttachmentTemplate(replicatedStorage, effectName)
	if not template then
		return false
	end

	local effect = template:Clone()
	effect.Parent = swordPart
	InstanceUtil.EmitParticles(effect)
	InstanceUtil.DestroyAfter(effect, 4)
	return true
end

function module.PlayIndication(
	replicatedStorage: ReplicatedStorage,
	params: any,
	forcedIndicator: string?
): boolean
	local character = resolveCharacter(params)
	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local indicatorKey = forcedIndicator
	if not indicatorKey and typeof(params) == "table" then
		indicatorKey = params.indicator or params.Indicator or params.color or params.Color or params[2]
	end

	local effectName = resolveIndicatorEffectName(indicatorKey)
	local template = AssetResolver.ResolveHitAttachmentTemplate(replicatedStorage, effectName)
	if not template then
		return false
	end

	local effect = template:Clone()
	effect.Parent = rootPart

	local lifeTime = 4
	if typeof(params) == "table" then
		lifeTime = tonumber(params.duration or params.Duration or params.time or params.Time or params[3]) or lifeTime
	end

	InstanceUtil.EmitParticles(effect)
	InstanceUtil.DestroyAfter(effect, lifeTime)
	return true
end

function module.PlayHumanHit(replicatedStorage: ReplicatedStorage, paramsOrCharacter: any, lifeTime: number?): boolean
	local character = resolveCharacter(paramsOrCharacter)
	if not character then
		return false
	end

	local template = AssetResolver.ResolveHumanHitTemplate(replicatedStorage)
	if not template then
		return false
	end

	local torso = character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") then
		return false
	end

	local effect = template:Clone()
	effect.Parent = torso
	InstanceUtil.EmitParticles(effect)
	InstanceUtil.DestroyAfter(effect, tonumber(lifeTime) or 5)
	return true
end

function module.PlayDodge(replicatedStorage: ReplicatedStorage, paramsOrCharacter: any): boolean
	local character = resolveCharacter(paramsOrCharacter)
	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local template = AssetResolver.ResolveDodgeTemplate(replicatedStorage)
	if not template then
		return false
	end

	local dodgeEffect = template:Clone()
	local primaryPart = InstanceUtil.ResolvePrimaryPart(dodgeEffect)
	if primaryPart then
		primaryPart.Anchored = false
		primaryPart.CanCollide = false
		primaryPart.CanTouch = false
		primaryPart.CFrame = rootPart.CFrame
	end

	if dodgeEffect:IsA("Attachment") then
		dodgeEffect.Parent = rootPart
	else
		dodgeEffect.Parent = character
	end

	local effectPart = InstanceUtil.ResolvePrimaryPart(dodgeEffect)
	if effectPart then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = effectPart
		weld.Parent = effectPart
		InstanceUtil.DestroyAfter(weld, 3)
	end

	InstanceUtil.EmitParticles(dodgeEffect)
	InstanceUtil.DestroyAfter(dodgeEffect, 3)
	return true
end

function module.PlaySlowStunned(
	replicatedStorage: ReplicatedStorage,
	paramsOrCharacter: any,
	fallbackLifeTime: number?
): boolean
	local character = resolveCharacter(paramsOrCharacter)
	if not character then
		return false
	end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false
	end

	local template = AssetResolver.ResolveSlowStunnedTemplate(replicatedStorage)
	if not template then
		return false
	end

	local effect = template:Clone()
	effect.Parent = head

	local lifeTime = tonumber(fallbackLifeTime) or 3
	if typeof(paramsOrCharacter) == "table" then
		local data = paramsOrCharacter[2]
		if typeof(data) == "table" then
			lifeTime = tonumber(data.Duration or data.duration or data.time or data.Time or data[1]) or lifeTime
		end

		lifeTime = tonumber(paramsOrCharacter.Duration or paramsOrCharacter.duration or paramsOrCharacter[3]) or lifeTime
	end

	for _, descendant in ipairs(effect:GetDescendants()) do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		local emitCount = tonumber(descendant:GetAttribute("EmitCount")) or 1
		local emitDelay = tonumber(descendant:GetAttribute("EmitDelay"))
		local safeEmitCount = math.max(1, math.floor(emitCount))

		if emitDelay and emitDelay > 0 then
			task.delay(emitDelay, function()
				if descendant and descendant.Parent then
					descendant:Emit(safeEmitCount)
				end
			end)
		else
			descendant:Emit(safeEmitCount)
		end
	end

	InstanceUtil.DestroyAfter(effect, lifeTime)
	return true
end

return table.freeze(module)
