local module = {}

local ActionUtil = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("ActionUtil"))
local SkillAnimUtil = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("SkillAnimUtil"))
local SkillVfxUtil = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("SkillVfxUtil"))
local Config = require(script:WaitForChild("Config"))

local KEYFRAMES = Config.Keyframes
local VFX_OFFSETS = Config.VfxOffsets
local DEFAULTS = Config.Defaults

local function getSettingsNumber(settings: { [string]: any }, key: string, fallback: number): number
	local value = settings[key]
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

local function getActionNumber(M1Calc, weaponStats: { [string]: any }, suffix: string, fallback: number): number
	return M1Calc.ToNumber(weaponStats["RendStep" .. suffix], fallback)
end

local function getActionVector3(weaponStats: { [string]: any }, suffix: string, fallback: Vector3): Vector3
	local value = weaponStats["RendStep" .. suffix]
	if typeof(value) == "Vector3" then
		return value
	end
	return fallback
end

local function getActionCFrame(weaponStats: { [string]: any }, suffix: string, fallback: CFrame): CFrame
	local value = weaponStats["RendStep" .. suffix]
	if typeof(value) == "CFrame" then
		return value
	end
	return fallback
end

local function canTargetCharacter(sourceCharacter: Model, targetCharacter: Model): boolean
	if targetCharacter == sourceCharacter then
		return false
	end

	local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	if targetCharacter:GetAttribute("Downed") == true or targetCharacter:GetAttribute("IsRagdoll") == true then
		return false
	end
	if targetCharacter:GetAttribute("iFrames") == true then
		return false
	end

	return true
end

local function collectCandidateCharactersNear(
	sourceCharacter: Model,
	sourceRoot: BasePart,
	maxDistance: number
): { Model }
	local candidates = {}
	local seen: { [Model]: boolean } = {}

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { sourceCharacter }
	overlapParams.MaxParts = 160

	for _, part in ipairs(workspace:GetPartBoundsInRadius(sourceRoot.Position, maxDistance, overlapParams)) do
		local candidate = part:FindFirstAncestorOfClass("Model")
		if not candidate or seen[candidate] then
			continue
		end
		if not canTargetCharacter(sourceCharacter, candidate) then
			continue
		end

		seen[candidate] = true
		table.insert(candidates, candidate)
	end

	return candidates
end

local function findClosestTargetInCone(sourceCharacter: Model, maxDistance: number, coneAngle: number): Model?
	local sourceRoot = sourceCharacter:FindFirstChild("HumanoidRootPart")
	if not sourceRoot or not sourceRoot:IsA("BasePart") then
		return nil
	end

	local bestTarget = nil
	local bestDistance = maxDistance
	local lookVector = sourceRoot.CFrame.LookVector

	for _, candidate in ipairs(collectCandidateCharactersNear(sourceCharacter, sourceRoot, maxDistance)) do
		local rootPart = candidate:FindFirstChild("HumanoidRootPart")
		if not rootPart or not rootPart:IsA("BasePart") then
			continue
		end

		local toTarget = rootPart.Position - sourceRoot.Position
		local distance = toTarget.Magnitude
		if distance <= 0 or distance > maxDistance then
			continue
		end

		local direction = toTarget.Unit
		local dot = math.clamp(lookVector:Dot(direction), -1, 1)
		local angle = math.deg(math.acos(dot))
		if angle <= (coneAngle * 0.5) and distance < bestDistance then
			bestDistance = distance
			bestTarget = candidate
		end
	end

	return bestTarget
end

local function isDefenseActive(character: Model): boolean
	return character:GetAttribute("Parrying") == true
		or character:GetAttribute("isBlocking") == true
		or character:GetAttribute("AutoParryActive") == true
end

function module.Execute(service, context)
	local M1Calc = service.M1Calc
	local CombatNet = service.CombatNet

	local player: Player = context.player
	local character: Model = context.character
	local humanoid: Humanoid = context.humanoid
	local rootPart: BasePart = context.rootPart
	local equippedTool: Tool = context.equippedTool
	local weaponStats = context.weaponStats or {}
	local settings = service.Settings

	local actionName = Config.ActionName
	local cooldownDuration = math.max(0, getActionNumber(M1Calc, weaponStats, "Cooldown", DEFAULTS.Cooldown))
	local attackWalkSpeed = math.max(0, getActionNumber(M1Calc, weaponStats, "WalkSpeed", DEFAULTS.AttackWalkSpeed))
	local startupSwingSpeed =
		math.max(0.01, getActionNumber(M1Calc, weaponStats, "StartupSwingSpeed", DEFAULTS.StartupSwingSpeed))
	local hitSwingSpeed = math.max(0.01, getActionNumber(M1Calc, weaponStats, "HitSwingSpeed", DEFAULTS.HitSwingSpeed))
	local missSwingSpeed =
		math.max(0.01, getActionNumber(M1Calc, weaponStats, "MissSwingSpeed", DEFAULTS.MissSwingSpeed))
	local stateReleasePadding = math.max(
		0,
		getActionNumber(
			M1Calc,
			weaponStats,
			"StateReleasePadding",
			getSettingsNumber(settings, "StateReleasePadding", DEFAULTS.StateReleasePadding)
		)
	)
	local hitboxFallbackDelay = math.max(
		0.02,
		getActionNumber(
			M1Calc,
			weaponStats,
			"HitboxFallbackDelay",
			getSettingsNumber(settings, "HitboxFallbackDelay", DEFAULTS.HitboxFallbackDelay)
		)
	)

	local damage = M1Calc.ResolveDamage(player, weaponStats.RendStepDamage or weaponStats.Damage or DEFAULTS.Damage)
	local knockbackStrength = math.max(0, getActionNumber(M1Calc, weaponStats, "KB", DEFAULTS.Knockback))
	local stunDuration = math.max(0, getActionNumber(M1Calc, weaponStats, "Stun", DEFAULTS.Stun))
	local comboForReaction =
		math.max(1, math.floor(getActionNumber(M1Calc, weaponStats, "ComboForReaction", DEFAULTS.ComboForReaction)))

	local hitboxSize = getActionVector3(weaponStats, "HitboxSize", DEFAULTS.HitboxSize)
	local hitboxOffset = getActionCFrame(weaponStats, "HitboxOffset", DEFAULTS.HitboxOffset)

	local targetDistance = math.max(4, getActionNumber(M1Calc, weaponStats, "TargetDistance", DEFAULTS.TargetDistance))
	local targetConeAngle = math.clamp(
		getActionNumber(M1Calc, weaponStats, "TargetConeAngle", DEFAULTS.TargetConeAngle),
		10,
		180
	)
	local missDashSpeed = math.max(0, getActionNumber(M1Calc, weaponStats, "MissDashSpeed", DEFAULTS.MissDashSpeed))
	local missDashDuration =
		math.max(0.05, getActionNumber(M1Calc, weaponStats, "MissDashDuration", DEFAULTS.MissDashDuration))
	local hitStepDistance =
		math.max(0, getActionNumber(M1Calc, weaponStats, "HitStepDistance", DEFAULTS.HitStepDistance))
	local teleportBehindDistance = math.max(
		1.5,
		getActionNumber(M1Calc, weaponStats, "TeleportBehindDistance", DEFAULTS.TeleportBehindDistance)
	)
	local indicatorColor = string.lower(tostring(weaponStats.RendStepIndicatorColor or DEFAULTS.IndicatorColor or "red"))

	local token, startErr = service:StartAttack(context, {
		actionName = actionName,
		cooldownDuration = cooldownDuration,
		attackWalkSpeed = attackWalkSpeed,
	})
	if not token then
		return false, startErr
	end

	service:ReplicateWeaponaryEffect(
		"Indication",
		CombatNet.MakeIndicatorPayload(character, indicatorColor),
		{ character },
		{ player }
	)

	character:SetAttribute("UsingMove", true)

	local hyperArmorDuration =
		math.max(0.1, getActionNumber(M1Calc, weaponStats, "InvulnerableDuration", DEFAULTS.InvulnerableDuration))
	if service.HyperArmorService and typeof(service.HyperArmorService.Apply) == "function" then
		service.HyperArmorService:Apply(character, {
			type = "Invulnerable",
			duration = hyperArmorDuration,
			source = actionName,
			includePlayers = { player },
		})
	end

	local releaseScheduled = false
	local interruptedBeforeHit = false
	local hitTriggered = false
	local startupTrack: AnimationTrack? = nil
	local hitTrack: AnimationTrack? = nil
	local missTrack: AnimationTrack? = nil
	local startupKeyframeConn: RBXScriptConnection? = nil
	local hitKeyframeConn: RBXScriptConnection? = nil
	local disconnectInterruptConns = function() end

	local function disconnectSkillConns()
		if startupKeyframeConn and startupKeyframeConn.Connected then
			startupKeyframeConn:Disconnect()
		end
		startupKeyframeConn = nil

		if hitKeyframeConn and hitKeyframeConn.Connected then
			hitKeyframeConn:Disconnect()
		end
		hitKeyframeConn = nil
	end

	local function cleanupAndFinish()
		disconnectSkillConns()
		if character and character.Parent then
			character:SetAttribute("UsingMove", false)
			if service.HyperArmorService and typeof(service.HyperArmorService.Clear) == "function" then
				service.HyperArmorService:Clear(character, actionName, {
					replicate = true,
					includePlayers = { player },
				})
			end
		end
		service:FinishAttack(player, character, humanoid, token)
	end

	local function scheduleRelease(delaySeconds: number)
		if releaseScheduled then
			return
		end
		releaseScheduled = true
		disconnectInterruptConns()
		task.delay(math.max(0, delaySeconds), cleanupAndFinish)
	end

	local function markInterrupted()
		if interruptedBeforeHit then
			return
		end
		interruptedBeforeHit = true
		scheduleRelease(0)
	end

	disconnectInterruptConns = ActionUtil.BindInterruptSignals(character, humanoid, markInterrupted)

	local function canTriggerHit(): boolean
		if not service:IsAttackTokenCurrent(player, token) then
			return false
		end
		if not character or not character.Parent then
			return false
		end
		if interruptedBeforeHit then
			return false
		end
		if isDefenseActive(character) then
			return false
		end
		return true
	end

	local function replicateTeleportVfx()
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = true, [2] = false, [3] = false },
			VFX_OFFSETS.TeleportOne,
			"Emit",
			{ character }
		)
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = false, [2] = true, [3] = false },
			VFX_OFFSETS.TeleportTwo,
			"Emit",
			{ character }
		)
	end

	local function replicateHitVfx()
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = false, [2] = false, [3] = true },
			VFX_OFFSETS.Hit,
			"Emit",
			{ character }
		)
	end

	local function triggerHit(stepDirection: Vector3?)
		if hitTriggered then
			return
		end
		if not canTriggerHit() then
			return
		end

		hitTriggered = true
		character:SetAttribute("Attacking", false)

		replicateHitVfx()
		service:PlayWeaponSound(character, equippedTool.Name, { "MeleHit", "AirSwing", "swing1" }, rootPart)

		service:SpawnHitbox({
			player = player,
			character = character,
			rootPart = rootPart,
			weaponStats = weaponStats,
			attackerToolName = equippedTool.Name,
			damage = damage,
			hitboxSize = hitboxSize,
			hitboxOffset = hitboxOffset,
			activeTime = getActionNumber(
				M1Calc,
				weaponStats,
				"HitboxActiveTime",
				getSettingsNumber(settings, "HitboxActiveTime", DEFAULTS.HitboxActiveTime)
			),
			hitProfile = {
				knockbackStrength = knockbackStrength,
				stunDuration = stunDuration,
				ragdoll = false,
				ragdollDuration = 0,
				comboForReaction = comboForReaction,
				guardBreakOnBlock = false,
			},
		})

		if typeof(stepDirection) == "Vector3" and stepDirection.Magnitude > 0 then
			local direction = stepDirection.Unit
			local movePos = rootPart.Position + (direction * hitStepDistance)
			rootPart.CFrame = CFrame.new(movePos, movePos + direction)
		end
	end

	local function playMissSequence()
		if releaseScheduled then
			return
		end
		if not service:IsAttackTokenCurrent(player, token) then
			return
		end

		local flatLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		if flatLook.Magnitude > 0 then
			service:ApplyPush(character, {
				direction = flatLook,
				speed = missDashSpeed,
				duration = missDashDuration,
				maxForce = math.max(1200, missDashSpeed * 1500),
			})
		end

		local missAnimation = SkillAnimUtil.ResolveSkillAnimation(service, { "MeleStartUpMiss", "RendStepMiss" })
		if not missAnimation then
			task.delay(missDashDuration + stateReleasePadding, function()
				scheduleRelease(0)
			end)
			return
		end

		missTrack = service.AnimUtil.LoadTrack(humanoid, missAnimation, "RendStepMiss")
		if not missTrack then
			task.delay(missDashDuration + stateReleasePadding, function()
				scheduleRelease(0)
			end)
			return
		end

		missTrack.Priority = settings.AttackTrackPriority
		missTrack:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
		missTrack:AdjustSpeed(missSwingSpeed)
		missTrack.Stopped:Connect(function()
			scheduleRelease(stateReleasePadding)
		end)
	end

	local function playHitSequence(targetCharacter: Model)
		if releaseScheduled then
			return
		end
		if not service:IsAttackTokenCurrent(player, token) then
			return
		end

		local startPos = rootPart.Position
		local storedDirection: Vector3? = nil
		local hitAnimation = SkillAnimUtil.ResolveSkillAnimation(service, { "MeleStartUpHit", "RendStepHit", "RendStep" })
		if not hitAnimation then
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
			if targetRoot and targetRoot:IsA("BasePart") then
				local direction = targetRoot.Position - startPos
				if direction.Magnitude > 0 then
					storedDirection = direction.Unit
					local destination = targetRoot.Position - storedDirection * teleportBehindDistance
					rootPart.CFrame = CFrame.new(destination, targetRoot.Position)
				end
			end
			triggerHit(storedDirection)
			scheduleRelease(stateReleasePadding)
			return
		end

		hitTrack = service.AnimUtil.LoadTrack(humanoid, hitAnimation, "RendStepHit")
		if not hitTrack then
			scheduleRelease(stateReleasePadding)
			return
		end

		hitTrack.Priority = settings.AttackTrackPriority
		hitTrack:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
		hitTrack:AdjustSpeed(hitSwingSpeed)

		hitKeyframeConn = hitTrack.KeyframeReached:Connect(function(keyframeName)
			local key = string.lower(tostring(keyframeName))
			if KEYFRAMES.Teleport[key] then
				local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
				if not targetRoot or not targetRoot:IsA("BasePart") then
					return
				end

				local direction = targetRoot.Position - startPos
				if direction.Magnitude > 0 then
					storedDirection = direction.Unit
				else
					local fallbackDirection = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
					if fallbackDirection.Magnitude > 0 then
						storedDirection = fallbackDirection.Unit
					end
				end

				if storedDirection then
					local destination = targetRoot.Position - storedDirection * teleportBehindDistance
					rootPart.CFrame = CFrame.new(destination, targetRoot.Position)
				end
				return
			end

			if KEYFRAMES.Hit[key] then
				triggerHit(storedDirection)
			end
		end)

		hitTrack.Stopped:Connect(function()
			if hitKeyframeConn and hitKeyframeConn.Connected then
				hitKeyframeConn:Disconnect()
			end
			hitKeyframeConn = nil

			if not hitTriggered then
				triggerHit(storedDirection)
			end
			scheduleRelease(stateReleasePadding)
		end)
	end

	local function onStartupEnded()
		if interruptedBeforeHit then
			return
		end
		if not service:IsAttackTokenCurrent(player, token) then
			return
		end

		service:PlayWeaponSound(character, equippedTool.Name, { "MeleTP" }, rootPart)
		replicateTeleportVfx()

		local targetCharacter = findClosestTargetInCone(character, targetDistance, targetConeAngle)
		if targetCharacter and targetCharacter.Parent then
			playHitSequence(targetCharacter)
		else
			playMissSequence()
		end
	end

	local startupAnimation = SkillAnimUtil.ResolveSkillAnimation(service, { "MeleStartUp", "RendStep" })
	local hasStartupTrack = false

	if startupAnimation then
		startupTrack = service.AnimUtil.LoadTrack(humanoid, startupAnimation, "RendStepStartup")
		if startupTrack then
			hasStartupTrack = true
			startupTrack.Priority = settings.AttackTrackPriority
			startupTrack:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
			startupTrack:AdjustSpeed(startupSwingSpeed)

			startupTrack.Stopped:Connect(function()
				onStartupEnded()
			end)
		end
	end

	if not hasStartupTrack then
		task.delay(hitboxFallbackDelay, function()
			onStartupEnded()
		end)
	end

	local failsafeDelay = math.max(1.8, getActionNumber(M1Calc, weaponStats, "FailsafeRelease", DEFAULTS.FailsafeRelease))
	task.delay(failsafeDelay, function()
		if service:IsAttackTokenCurrent(player, token) then
			scheduleRelease(0)
		end
	end)

	return true
end

return table.freeze(module)
