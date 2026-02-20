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
	return M1Calc.ToNumber(weaponStats["Strikefall" .. suffix], fallback)
end

local function getActionVector3(weaponStats: { [string]: any }, suffix: string, fallback: Vector3): Vector3
	local value = weaponStats["Strikefall" .. suffix]
	if typeof(value) == "Vector3" then
		return value
	end
	return fallback
end

local function getActionCFrame(weaponStats: { [string]: any }, suffix: string, fallback: CFrame): CFrame
	local value = weaponStats["Strikefall" .. suffix]
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

local function toLowerKeyframeName(keyframeName: any): string
	return string.lower(tostring(keyframeName))
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
	local openingSwingSpeed =
		math.max(0.01, getActionNumber(M1Calc, weaponStats, "OpeningSwingSpeed", DEFAULTS.OpeningSwingSpeed))
	local comboSwingSpeed = math.max(0.01, getActionNumber(M1Calc, weaponStats, "ComboSwingSpeed", DEFAULTS.ComboSwingSpeed))
	local comboFirstSwingSpeed =
		math.max(0.01, getActionNumber(M1Calc, weaponStats, "ComboFirstSwingSpeed", DEFAULTS.ComboFirstSwingSpeed))
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
	local openingHitboxActiveTime = math.max(
		0.03,
		getActionNumber(
			M1Calc,
			weaponStats,
			"OpeningHitboxActiveTime",
			getSettingsNumber(settings, "HitboxActiveTime", DEFAULTS.OpeningHitboxActiveTime)
		)
	)
	local comboHitboxActiveTime = math.max(
		0.03,
		getActionNumber(
			M1Calc,
			weaponStats,
			"ComboHitboxActiveTime",
			getSettingsNumber(settings, "HitboxActiveTime", DEFAULTS.ComboHitboxActiveTime)
		)
	)

	local comboForReaction =
		math.max(1, math.floor(getActionNumber(M1Calc, weaponStats, "ComboForReaction", DEFAULTS.ComboForReaction)))
	local openingDamage = M1Calc.ResolveDamage(player, weaponStats.StrikefallDamage or weaponStats.Damage or DEFAULTS.Damage)
	local comboHitOneDamage = M1Calc.ResolveDamage(
		player,
		weaponStats.StrikefallComboHitOneDamage or weaponStats.StrikefallSecondDamage or weaponStats.StrikefallDamage
			or weaponStats.Damage
			or DEFAULTS.Damage
	)
	local comboHitTwoDamage = M1Calc.ResolveDamage(
		player,
		weaponStats.StrikefallComboHitTwoDamage or weaponStats.StrikefallSecondDamage or weaponStats.StrikefallDamage
			or weaponStats.Damage
			or DEFAULTS.Damage
	)

	local openingHitboxSize = getActionVector3(weaponStats, "HitboxSize", DEFAULTS.OpeningHitboxSize)
	local openingHitboxOffset = getActionCFrame(weaponStats, "HitboxOffset", DEFAULTS.OpeningHitboxOffset)
	local comboHitboxSize = getActionVector3(weaponStats, "ComboHitboxSize", DEFAULTS.ComboHitboxSize)
	local comboHitboxOffset = getActionCFrame(weaponStats, "ComboHitboxOffset", DEFAULTS.ComboHitboxOffset)

	local openingKnockback = math.max(0, getActionNumber(M1Calc, weaponStats, "OpeningKB", DEFAULTS.OpeningKnockback))
	local comboHitOneKnockback =
		math.max(0, getActionNumber(M1Calc, weaponStats, "ComboHitOneKB", DEFAULTS.ComboHitOneKnockback))
	local comboHitTwoKnockback =
		math.max(0, getActionNumber(M1Calc, weaponStats, "ComboHitTwoKB", DEFAULTS.ComboHitTwoKnockback))
	local stunDuration = math.max(0, getActionNumber(M1Calc, weaponStats, "Stun", DEFAULTS.Stun))
	local openingForwardSpeed =
		math.max(0, getActionNumber(M1Calc, weaponStats, "ForwardSpeed", DEFAULTS.ForwardSpeed))
	local openingForwardDuration =
		math.max(0.02, getActionNumber(M1Calc, weaponStats, "ForwardDuration", DEFAULTS.ForwardDuration))
	local indicatorColor = string.lower(tostring(weaponStats.StrikefallIndicatorColor or DEFAULTS.IndicatorColor or "red"))

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
	service:ApplyPush(character, {
		direction = "Forward",
		planar = true,
		speed = openingForwardSpeed,
		duration = openingForwardDuration,
	})

	local trails = ActionUtil.CollectWeaponTrails(character, equippedTool)
	ActionUtil.SetTrailsEnabled(trails, true)

	local releaseScheduled = false
	local interruptedBeforeHit = false
	local openingHitTriggered = false
	local openingConnected = false
	local comboStarted = false
	local comboHitOneTriggered = false
	local comboHitTwoTriggered = false
	local openingTrack: AnimationTrack? = nil
	local comboTrack: AnimationTrack? = nil
	local openingKeyframeConn: RBXScriptConnection? = nil
	local comboKeyframeConn: RBXScriptConnection? = nil
	local disconnectInterruptConns = function() end

	local function disconnectKeyframeConns()
		if openingKeyframeConn and openingKeyframeConn.Connected then
			openingKeyframeConn:Disconnect()
		end
		openingKeyframeConn = nil

		if comboKeyframeConn and comboKeyframeConn.Connected then
			comboKeyframeConn:Disconnect()
		end
		comboKeyframeConn = nil
	end

	local function cleanupAndFinish()
		disconnectKeyframeConns()

		if character and character.Parent then
			character:SetAttribute("UsingMove", false)
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
		scheduleRelease(0)
	end

	disconnectInterruptConns = ActionUtil.BindInterruptSignals(character, humanoid, markInterrupted)

	local function replicateStrikeVfx(bamsOffset: CFrame)
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = true, [2] = false },
			bamsOffset,
			"Emit",
			{ character }
		)
		SkillVfxUtil.Replicate(
			service,
			actionName,
			character,
			player,
			{ [1] = false, [2] = true },
			VFX_OFFSETS.Cacas,
			"Emit",
			{ character }
		)
	end

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

	local startComboAnimation

	local function triggerComboHit(isSecondHit: boolean)
		if not canTriggerHit() then
			return
		end

		character:SetAttribute("Attacking", false)
		service:PlayWeaponSound(character, equippedTool.Name, { "AirSwing" }, rootPart)

		if isSecondHit then
			replicateStrikeVfx(VFX_OFFSETS.ComboHitTwoBams)
		else
			replicateStrikeVfx(VFX_OFFSETS.ComboHitOneBams)
		end

		service:SpawnHitbox({
			player = player,
			character = character,
			rootPart = rootPart,
			weaponStats = weaponStats,
			attackerToolName = equippedTool.Name,
			damage = isSecondHit and comboHitTwoDamage or comboHitOneDamage,
			hitboxSize = comboHitboxSize,
			hitboxOffset = comboHitboxOffset,
			activeTime = comboHitboxActiveTime,
			hitProfile = {
				knockbackStrength = isSecondHit and comboHitTwoKnockback or comboHitOneKnockback,
				stunDuration = stunDuration,
				ragdoll = false,
				ragdollDuration = 0,
				comboForReaction = comboForReaction,
				guardBreakOnBlock = false,
			},
		})
	end

	local function triggerOpeningHit()
		if openingHitTriggered then
			return
		end
		openingHitTriggered = true

		if not canTriggerHit() then
			return
		end

		character:SetAttribute("Attacking", false)
		service:PlayWeaponSound(character, equippedTool.Name, { "AirSwing" }, rootPart)
		replicateStrikeVfx(VFX_OFFSETS.OpeningBams)

		service:SpawnHitbox({
			player = player,
			character = character,
			rootPart = rootPart,
			weaponStats = weaponStats,
			attackerToolName = equippedTool.Name,
			damage = openingDamage,
			hitboxSize = openingHitboxSize,
			hitboxOffset = openingHitboxOffset,
			activeTime = openingHitboxActiveTime,
			hitProfile = {
				knockbackStrength = openingKnockback,
				stunDuration = stunDuration,
				ragdoll = false,
				ragdollDuration = 0,
				comboForReaction = comboForReaction,
				guardBreakOnBlock = false,
			},
			onHit = function()
				if openingConnected then
					return
				end
				openingConnected = true

				if openingTrack and openingTrack.IsPlaying then
					openingTrack:Stop()
				end
				task.defer(startComboAnimation)
			end,
		})

		task.delay(math.max(0.08, openingHitboxActiveTime + 0.05), function()
			if openingConnected or comboStarted then
				return
			end
			scheduleRelease(stateReleasePadding)
		end)
	end

	startComboAnimation = function()
		if comboStarted or releaseScheduled then
			return
		end
		if not openingConnected then
			return
		end
		if not service:IsAttackTokenCurrent(player, token) then
			return
		end
		if interruptedBeforeHit then
			return
		end

		comboStarted = true
		local comboAnimation = SkillAnimUtil.ResolveSkillAnimation(service, { "MeleHit", "StrikefallCombo" })
		if not comboAnimation then
			triggerComboHit(false)
			task.delay(math.max(0.12, comboHitboxActiveTime), function()
				triggerComboHit(true)
				scheduleRelease(stateReleasePadding)
			end)
			return
		end

		comboTrack = service.AnimUtil.LoadTrack(humanoid, comboAnimation, "StrikefallCombo")
		if not comboTrack then
			scheduleRelease(stateReleasePadding)
			return
		end

		comboTrack.Priority = settings.AttackTrackPriority
		comboTrack:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
		comboTrack:AdjustSpeed(comboSwingSpeed)

		comboKeyframeConn = comboTrack.KeyframeReached:Connect(function(keyframeName)
			local key = toLowerKeyframeName(keyframeName)
			if (not comboHitOneTriggered) and KEYFRAMES.ComboHitOne[key] then
				comboHitOneTriggered = true
				comboTrack:AdjustSpeed(comboFirstSwingSpeed)
				triggerComboHit(false)
				return
			end

			if (not comboHitTwoTriggered) and KEYFRAMES.ComboHitTwo[key] then
				comboHitTwoTriggered = true
				comboTrack:AdjustSpeed(comboSwingSpeed)
				triggerComboHit(true)
			end
		end)

		comboTrack.Stopped:Connect(function()
			if comboKeyframeConn and comboKeyframeConn.Connected then
				comboKeyframeConn:Disconnect()
			end
			comboKeyframeConn = nil
			scheduleRelease(stateReleasePadding)
		end)
	end

	local openingAnimation = SkillAnimUtil.ResolveSkillAnimation(service, { "MeleCharge", "Strikefall" })
	local hasOpeningTrack = false

	if openingAnimation then
		openingTrack = service.AnimUtil.LoadTrack(humanoid, openingAnimation, "StrikefallOpening")
		if openingTrack then
			hasOpeningTrack = true
			openingTrack.Priority = settings.AttackTrackPriority
			openingTrack:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
			openingTrack:AdjustSpeed(openingSwingSpeed)

			openingKeyframeConn = openingTrack.KeyframeReached:Connect(function(keyframeName)
				local key = toLowerKeyframeName(keyframeName)
				if KEYFRAMES.OpeningHit[key] then
					triggerOpeningHit()
				end
			end)

			openingTrack.Stopped:Connect(function()
				if openingKeyframeConn and openingKeyframeConn.Connected then
					openingKeyframeConn:Disconnect()
				end
				openingKeyframeConn = nil

				if not openingHitTriggered then
					triggerOpeningHit()
				end

				if openingConnected and not comboStarted then
					startComboAnimation()
					return
				end

				if not comboStarted then
					scheduleRelease(stateReleasePadding)
				end
			end)
		end
	end

	if not hasOpeningTrack then
		task.delay(hitboxFallbackDelay, function()
			triggerOpeningHit()
			task.delay(math.max(0.1, openingHitboxActiveTime + 0.05), function()
				if openingConnected and not comboStarted then
					startComboAnimation()
				elseif not comboStarted then
					scheduleRelease(stateReleasePadding)
				end
			end)
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
