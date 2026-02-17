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

function HitService.Hit(enemyHumanoid, damage, stunDuration, knockback, ragdoll, ragdollDuration, elementalEffect)
	if not enemyHumanoid or not enemyHumanoid.Parent then
		return
	end

	local enemyChar = enemyHumanoid.Parent
	local enemyRoot = enemyChar:FindFirstChild("HumanoidRootPart")

	if not Combat then
		Combat = getCombatApi()
	end

	tryForceStopCarryGrip(enemyChar)

	if damage and damage ~= 0 then
		RegenManager:ApplyDamage(enemyHumanoid, damage)
		if enemyRoot then
			enemyRoot.Anchored = false
		end
	end

	if ragdoll then
		applyRagdoll(enemyHumanoid, ragdollDuration or 0)
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
