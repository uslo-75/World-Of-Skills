local HitService = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local modules = ServerStorage:WaitForChild("Module")
local stunHandler = require(modules:WaitForChild("StunHandlerV2"))

local RegenManager =
	require(ServerScriptService:WaitForChild("Server"):WaitForChild("Handler"):WaitForChild("RegenManager"))

local function getCombatApi()
	local server = ServerScriptService:FindFirstChild("Server")
	local handler = server and server:FindFirstChild("Handler")
	local combatModule = handler and handler:FindFirstChild("Combat")

	if not combatModule or not combatModule:IsA("ModuleScript") then
		return nil
	end

	local ok, api = pcall(require, combatModule)
	if not ok then
		warn("[HitService] Failed to require Combat:", api)
		return nil
	end
	return api
end

local Combat = getCombatApi()

local DEFAULT_WALKSPEED = 9
local DEFAULT_JUMPPOWER = 6.2

local ATTR_HYPERARMOR_TYPE = "HyperArmorType"
local ATTR_HYPERARMOR_EXPIRES_AT = "HyperArmorExpiresAt"
local ATTR_HYPERARMOR_DAMAGE_MULT = "HyperArmorDamageMultiplier"
local ATTR_HYPERARMOR_NO_RAGDOLL = "HyperArmorNoRagdoll"

local function clearHyperArmor(enemyChar)
	enemyChar:SetAttribute(ATTR_HYPERARMOR_TYPE, nil)
	enemyChar:SetAttribute(ATTR_HYPERARMOR_EXPIRES_AT, nil)
	enemyChar:SetAttribute(ATTR_HYPERARMOR_DAMAGE_MULT, nil)
	enemyChar:SetAttribute(ATTR_HYPERARMOR_NO_RAGDOLL, nil)
	enemyChar:SetAttribute("HyperArmorSource", nil)
end

local function getActiveHyperArmor(enemyChar)
	if not enemyChar or not enemyChar.Parent then
		return nil
	end

	local armorType = enemyChar:GetAttribute(ATTR_HYPERARMOR_TYPE)
	if typeof(armorType) ~= "string" or armorType == "" then
		return nil
	end

	local expiresAt = tonumber(enemyChar:GetAttribute(ATTR_HYPERARMOR_EXPIRES_AT)) or 0
	if expiresAt > 0 and os.clock() >= expiresAt then
		clearHyperArmor(enemyChar)
		return nil
	end

	return {
		type = armorType,
		damageMultiplier = math.clamp(tonumber(enemyChar:GetAttribute(ATTR_HYPERARMOR_DAMAGE_MULT)) or 1, 0, 1),
		noRagdoll = enemyChar:GetAttribute(ATTR_HYPERARMOR_NO_RAGDOLL) == true,
	}
end

local function resolveDamageWithHyperArmor(enemyChar, damage, ragdoll, ragdollDuration, bypassHyperArmor)
	local adjustedDamage = tonumber(damage) or 0
	local adjustedRagdoll = ragdoll == true
	local adjustedRagdollDuration = ragdollDuration or 0

	if bypassHyperArmor then
		return adjustedDamage, adjustedRagdoll, adjustedRagdollDuration, false
	end

	-- Keep non-damage system stuns (parry/guardbreak flow) unaffected.
	if adjustedDamage <= 0 and not adjustedRagdoll then
		return adjustedDamage, adjustedRagdoll, adjustedRagdollDuration, false
	end

	local armorState = getActiveHyperArmor(enemyChar)
	if not armorState then
		return adjustedDamage, adjustedRagdoll, adjustedRagdollDuration, false
	end

	local armorType = string.lower(armorState.type)
	if armorType == "invulnerable" then
		return 0, false, 0, true
	end

	adjustedDamage = adjustedDamage * armorState.damageMultiplier
	if armorState.noRagdoll then
		adjustedRagdoll = false
		adjustedRagdollDuration = 0
	end

	return adjustedDamage, adjustedRagdoll, adjustedRagdollDuration, false
end

local function tryForceStopCarryGrip(enemyChar)
	if not Combat then
		return
	end
	if not enemyChar or not enemyChar.Parent then
		return
	end

	local enemyPlayer = Players:GetPlayerFromCharacter(enemyChar)
	if not enemyPlayer then
		return
	end

	if enemyChar:GetAttribute("Carrying") == true and Combat.Carry and Combat.Carry.ForceStop then
		Combat.Carry:ForceStop(enemyPlayer)
	end

	if enemyChar:GetAttribute("Gripping") == true and Combat.Grip and Combat.Grip.ForceStop then
		Combat.Grip:ForceStop(enemyPlayer)
	end
end

local function applyKnockback(rootPart, velocity)
	if not rootPart or not rootPart.Parent then
		return
	end

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
	bv.P = 50000
	bv.Velocity = velocity
	bv.Parent = rootPart

	task.delay(0.2, function()
		if bv and bv.Parent then
			bv:Destroy()
		end
	end)
end

local function applyRagdoll(enemyHumanoid, duration)
	local char = enemyHumanoid and enemyHumanoid.Parent
	if not char then
		return
	end

	task.spawn(function()
		if not enemyHumanoid.Parent then
			return
		end

		char:SetAttribute("IsRagdoll", false)
		char:SetAttribute("IsRagdoll", true)

		task.wait(duration or 0)

		if not enemyHumanoid.Parent then
			return
		end

		char:SetAttribute("IsRagdoll", false)
		char:SetAttribute("iFrames", true)

		if enemyHumanoid.Health > 0 then
			task.delay(0.3, function()
				if char and char.Parent then
					char:SetAttribute("iFrames", false)
				end
			end)
		end
	end)
end

local function applyBurn(enemyHumanoid)
	local char = enemyHumanoid and enemyHumanoid.Parent
	if not char then
		return
	end

	task.spawn(function()
		if not enemyHumanoid.Parent then
			return
		end
		if char:GetAttribute("Burning") == true then
			return
		end

		char:SetAttribute("Burning", true)

		local burnDuration = math.random(2, 5)
		local startTime = os.clock()
		local dmg = math.random(1, 2)

		while (os.clock() - startTime) < burnDuration do
			if not enemyHumanoid.Parent or enemyHumanoid.Health <= 0 then
				break
			end

			RegenManager:ApplyDamage(enemyHumanoid, dmg)
			task.wait(2)

			if not char.Parent or char:GetAttribute("Burning") ~= true then
				break
			end
		end

		if char and char.Parent then
			char:SetAttribute("Burning", false)
		end
	end)
end

function HitService.Hit(enemyHumanoid, damage, stunDuration, knockback, ragdoll, ragdollDuration, elementalEffect, bypassHyperArmor)
	if not enemyHumanoid or not enemyHumanoid.Parent then
		return
	end

	local enemyChar = enemyHumanoid.Parent
	local enemyRoot = enemyChar:FindFirstChild("HumanoidRootPart")
	local resolvedDamage, resolvedRagdoll, resolvedRagdollDuration, blockedByInvulnerable =
		resolveDamageWithHyperArmor(enemyChar, damage, ragdoll, ragdollDuration, bypassHyperArmor)
	if blockedByInvulnerable then
		return
	end

	if not Combat then
		Combat = getCombatApi()
	end

	tryForceStopCarryGrip(enemyChar)

	if resolvedDamage and resolvedDamage ~= 0 then
		RegenManager:ApplyDamage(enemyHumanoid, resolvedDamage)
		if enemyRoot then
			enemyRoot.Anchored = false
		end
	end

	if resolvedRagdoll then
		applyRagdoll(enemyHumanoid, resolvedRagdollDuration or 0)
	end

	if stunDuration and stunDuration > 0 then
		enemyHumanoid.WalkSpeed = DEFAULT_WALKSPEED
		enemyHumanoid.JumpPower = DEFAULT_JUMPPOWER
		stunHandler.Stun(enemyHumanoid, stunDuration)
	end

	if knockback then
		applyKnockback(enemyRoot, knockback)
	end

	if elementalEffect then
		applyBurn(enemyHumanoid)
	end

	if enemyChar and enemyChar.Parent then
		enemyChar:SetAttribute("Attacking", false)
		enemyChar:SetAttribute("Swing", false)
	end
end

return HitService
