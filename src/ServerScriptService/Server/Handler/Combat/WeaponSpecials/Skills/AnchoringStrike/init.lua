local RunService = game:GetService("RunService")

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
	return M1Calc.ToNumber(weaponStats["AnchoringStrike" .. suffix], fallback)
end

local function getActionVector3(weaponStats: { [string]: any }, suffix: string, fallback: Vector3): Vector3
	local value = weaponStats["AnchoringStrike" .. suffix]
	if typeof(value) == "Vector3" then
		return value
	end
	return fallback
end

local function getActionCFrame(weaponStats: { [string]: any }, suffix: string, fallback: CFrame): CFrame
	local value = weaponStats["AnchoringStrike" .. suffix]
	if typeof(value) == "CFrame" then
		return value
	end
	return fallback
end

local function isDefenseActive(character: Model): boolean
	return character:GetAttribute("Parrying") == true
		or character:GetAttribute("isBlocking") == true
		or character:GetAttribute("AutoParryActive") == true
end

local function pullTargetToFrontPlanar(attackerRoot: BasePart, targetCharacter: Model, pull: { [string]: number })
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then
		return
	end

	local pullDistance = math.max(1.5, tonumber(pull.distance) or DEFAULTS.PullDistance)
	local pullDuration = math.max(0.03, tonumber(pull.duration) or DEFAULTS.PullDuration)
	local pullForce = math.max(8000, tonumber(pull.maxForce) or DEFAULTS.PullForce)
	local pullMaxSpeed = math.max(1, tonumber(pull.maxSpeed) or DEFAULTS.PullMaxSpeed)
	local stopDistance = math.max(0.1, tonumber(pull.stopDistance) or DEFAULTS.PullStopDistance)
	local verticalVelocityMax = tonumber(pull.verticalVelocityMax)
	if verticalVelocityMax == nil then
		verticalVelocityMax = DEFAULTS.PullVerticalVelocityMax
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "__AnchoringStrikePullAttachment"
	attachment.Parent = targetRoot

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "__AnchoringStrikePullVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(pullForce, 0, pullForce)
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = targetRoot

	local endAt = os.clock() + pullDuration
	local cleaned = false
	local conn: RBXScriptConnection? = nil

	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true

		if conn and conn.Connected then
			conn:Disconnect()
		end
		conn = nil

		if velocity and velocity.Parent then
			velocity:Destroy()
		end
		if attachment and attachment.Parent then
			attachment:Destroy()
		end
	end

	conn = RunService.Heartbeat:Connect(function()
		if not attackerRoot.Parent or not targetRoot.Parent then
			cleanup()
			return
		end

		local now = os.clock()
		if now >= endAt then
			cleanup()
			return
		end

		local destination = attackerRoot.Position + attackerRoot.CFrame.LookVector * pullDistance
		local toDestination = Vector3.new(destination.X - targetRoot.Position.X, 0, destination.Z - targetRoot.Position.Z)
		local planarDistance = toDestination.Magnitude

		if planarDistance <= stopDistance then
			velocity.VectorVelocity = Vector3.zero
		else
			local remaining = math.max(0.03, endAt - now)
			local desiredSpeed = math.min(pullMaxSpeed, planarDistance / remaining)
			velocity.VectorVelocity = toDestination.Unit * desiredSpeed
		end

		local currentVel = targetRoot.AssemblyLinearVelocity
		if currentVel.Y > verticalVelocityMax then
			targetRoot.AssemblyLinearVelocity = Vector3.new(currentVel.X, verticalVelocityMax, currentVel.Z)
		end
	end)

	task.delay(pullDuration + 0.06, cleanup)
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
	local swingSpeed = math.max(0.01, getActionNumber(M1Calc, weaponStats, "SwingSpeed", DEFAULTS.SwingSpeed))
	local hitSwingSpeed =
		math.max(0.01, getActionNumber(M1Calc, weaponStats, "HitSwingSpeed", DEFAULTS.HitSwingSpeed))
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

	local damage = M1Calc.ResolveDamage(player, weaponStats.AnchoringStrikeDamage or weaponStats.Damage or DEFAULTS.Damage)
	local knockbackStrength = math.max(0, getActionNumber(M1Calc, weaponStats, "KB", DEFAULTS.Knockback))
	local stunDuration = math.max(0, getActionNumber(M1Calc, weaponStats, "Stun", DEFAULTS.Stun))
	local comboForReaction =
		math.max(1, math.floor(getActionNumber(M1Calc, weaponStats, "ComboForReaction", DEFAULTS.ComboForReaction)))
	local hitboxSize = getActionVector3(weaponStats, "HitboxSize", DEFAULTS.HitboxSize)
	local hitboxOffset = getActionCFrame(weaponStats, "HitboxOffset", DEFAULTS.HitboxOffset)

	local pullConfig = {
		distance = math.max(1.5, getActionNumber(M1Calc, weaponStats, "PullDistance", DEFAULTS.PullDistance)),
		duration = math.max(0.06, getActionNumber(M1Calc, weaponStats, "PullDuration", DEFAULTS.PullDuration)),
		maxForce = math.max(8000, getActionNumber(M1Calc, weaponStats, "PullForce", DEFAULTS.PullForce)),
		maxSpeed = math.max(1, getActionNumber(M1Calc, weaponStats, "PullMaxSpeed", DEFAULTS.PullMaxSpeed)),
		stopDistance =
			math.max(0.1, getActionNumber(M1Calc, weaponStats, "PullStopDistance", DEFAULTS.PullStopDistance)),
		verticalVelocityMax = getActionNumber(
			M1Calc,
			weaponStats,
			"PullVerticalVelocityMax",
			DEFAULTS.PullVerticalVelocityMax
		),
	}

	local recoilSpeed = math.max(0, getActionNumber(M1Calc, weaponStats, "RecoilSpeed", DEFAULTS.RecoilSpeed))
	local recoilDuration = math.max(0.04, getActionNumber(M1Calc, weaponStats, "RecoilDuration", DEFAULTS.RecoilDuration))
	local hyperArmorDuration =
		math.max(0.1, getActionNumber(M1Calc, weaponStats, "HyperArmorDuration", DEFAULTS.HyperArmorDuration))
	local hyperArmorDamageMultiplier = math.clamp(
		getActionNumber(M1Calc, weaponStats, "HyperArmorDamageMultiplier", DEFAULTS.HyperArmorDamageMultiplier),
		0,
		1
	)
	local hitboxActiveTime = getActionNumber(
		M1Calc,
		weaponStats,
		"HitboxActiveTime",
		getSettingsNumber(settings, "HitboxActiveTime", DEFAULTS.HitboxActiveTime)
	)
	local failsafeDelay = math.max(1.8, getActionNumber(M1Calc, weaponStats, "FailsafeRelease", DEFAULTS.FailsafeRelease))
	local indicatorColor =
		string.lower(tostring(weaponStats.AnchoringStrikeIndicatorColor or DEFAULTS.IndicatorColor or "yellow"))

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
	if service.HyperArmorService and typeof(service.HyperArmorService.Apply) == "function" then
		service.HyperArmorService:Apply(character, {
			type = "Resilient",
			duration = hyperArmorDuration,
			damageMultiplier = hyperArmorDamageMultiplier,
			noRagdoll = true,
			source = actionName,
			includePlayers = { player },
		})
	end

	local trails = ActionUtil.CollectWeaponTrails(character, equippedTool)
	ActionUtil.SetTrailsEnabled(trails, false)

	local releaseScheduled = false
	local interruptedBeforeHit = false
	local hitTriggered = false
	local keyframeConn: RBXScriptConnection? = nil
	local disconnectInterruptConns = function() end

	local function replicateEmitVfx()
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = true, [2] = false, [3] = false },
			VFX_OFFSETS.Emit,
			"Emit",
			{ character }
		)
	end

	local function replicateEnableVfx()
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = false, [2] = true, [3] = false },
			VFX_OFFSETS.EnableOne,
			"EnableTrue",
			{ character }
		)
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = false, [2] = false, [3] = true },
			VFX_OFFSETS.EnableTwo,
			"EnableTrue",
			{ character }
		)
	end

	local function replicateDisableVfx()
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = false, [2] = true, [3] = true },
			nil,
			"EnableFalse",
			{ character }
		)
	end

	local function cleanupAndFinish()
		if keyframeConn and keyframeConn.Connected then
			keyframeConn:Disconnect()
		end
		keyframeConn = nil

		if character and character.Parent then
			character:SetAttribute("UsingMove", false)
			if service.HyperArmorService and typeof(service.HyperArmorService.Clear) == "function" then
				service.HyperArmorService:Clear(character, actionName, {
					replicate = true,
					includePlayers = { player },
				})
			end
		end
		ActionUtil.SetTrailsEnabled(trails, false)
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
		replicateDisableVfx()
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

	local function triggerHit()
		if hitTriggered then
			return
		end
		if not canTriggerHit() then
			return
		end

		hitTriggered = true
		character:SetAttribute("Attacking", false)
		service:PlayWeaponSound(character, equippedTool.Name, { "MeleHit", "AirSwing", "swing1" }, rootPart)
		service:PushVelocity(
			character,
			-rootPart.CFrame.LookVector * recoilSpeed,
			recoilDuration,
			math.max(1200, recoilSpeed * 1500)
		)

		service:SpawnHitbox({
			player = player,
			character = character,
			rootPart = rootPart,
			weaponStats = weaponStats,
			attackerToolName = equippedTool.Name,
			damage = damage,
			hitboxSize = hitboxSize,
			hitboxOffset = hitboxOffset,
			activeTime = hitboxActiveTime,
			hitProfile = {
				knockbackStrength = knockbackStrength,
				stunDuration = stunDuration,
				ragdoll = false,
				ragdollDuration = 0,
				comboForReaction = comboForReaction,
				guardBreakOnBlock = true,
			},
			onHit = function(targetCharacter: Model)
				pullTargetToFrontPlanar(rootPart, targetCharacter, pullConfig)
			end,
			onContact = function(targetCharacter: Model, didHit: boolean?)
				if didHit == true then
					return
				end
				if not targetCharacter or not targetCharacter.Parent then
					return
				end

				local guardBreakUntil = tonumber(targetCharacter:GetAttribute("GuardBreakUntil")) or 0
				if guardBreakUntil > os.clock() then
					pullTargetToFrontPlanar(rootPart, targetCharacter, pullConfig)
				end
			end,
		})
	end

	local attackAnimation = SkillAnimUtil.ResolveSkillAnimation(service, { "AnchoringStrike" })
	local hasTrack = false

	if attackAnimation then
		local track = service.AnimUtil.LoadTrack(humanoid, attackAnimation, "AnchoringStrike")
		if track then
			hasTrack = true
			track.Priority = settings.AttackTrackPriority
			track:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
			track:AdjustSpeed(swingSpeed)

			keyframeConn = track.KeyframeReached:Connect(function(keyframeName)
				local key = string.lower(tostring(keyframeName))
				if KEYFRAMES.Emit[key] then
					track:AdjustSpeed(1)
					replicateEmitVfx()
				elseif KEYFRAMES.Enable[key] then
					replicateEnableVfx()
				elseif KEYFRAMES.Hit[key] then
					track:AdjustSpeed(hitSwingSpeed)
					triggerHit()
				elseif KEYFRAMES.Stop[key] then
					replicateDisableVfx()
				end
			end)

			track.Stopped:Connect(function()
				if keyframeConn and keyframeConn.Connected then
					keyframeConn:Disconnect()
				end
				keyframeConn = nil

				replicateDisableVfx()
				scheduleRelease(stateReleasePadding)
			end)
		end
	end

	if not hasTrack then
		task.delay(hitboxFallbackDelay, function()
			replicateEmitVfx()
			replicateEnableVfx()
			triggerHit()
			replicateDisableVfx()
			scheduleRelease(stateReleasePadding)
		end)
	end

	task.delay(failsafeDelay, function()
		if service:IsAttackTokenCurrent(player, token) then
			replicateDisableVfx()
			scheduleRelease(0)
		end
	end)

	return true
end

return table.freeze(module)
