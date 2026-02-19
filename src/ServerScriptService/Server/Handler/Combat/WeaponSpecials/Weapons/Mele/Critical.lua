local module = {}
local ActionUtil = require(script.Parent.Parent.Parent:WaitForChild("Shared"):WaitForChild("ActionUtil"))

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

	-- Critical values come mostly from WeaponInfo (Heavy*), with local fallbacks.
	local comboForReaction = 4
	local damage = M1Calc.ResolveDamage(player, weaponStats.HeavyDamage or 8)
	local knockbackStrength = math.max(0, M1Calc.ToNumber(weaponStats.HeavyKB, 14))
	local stunDuration = math.max(0, M1Calc.ToNumber(weaponStats.HeavyStun, 0.7))
	local ragdoll = weaponStats.HeavyRagDoll == true
	local ragdollDuration = math.max(0, M1Calc.ToNumber(weaponStats.HeavyRagDuration, 0))
	local forwardSpeed = math.max(0, M1Calc.ToNumber(weaponStats.HeavyForwardSpeed, 12))
	local forwardDuration = math.max(0, M1Calc.ToNumber(weaponStats.HeavyForwardTime, 0.1))
	local cooldownDuration = math.max(0, M1Calc.ToNumber(weaponStats.HeavyCooldown, settings.DefaultCooldown))
	local attackWalkSpeed = math.max(0, M1Calc.ToNumber(weaponStats.HeavyWalkSpeed, settings.AttackWalkSpeed))
	local swingSpeed = math.max(0.01, M1Calc.ToNumber(weaponStats.CriticalSwingSpeed or weaponStats.SwingSpeed, settings.DefaultSwingSpeed))
	local stateReleasePadding = math.max(0, M1Calc.ToNumber(weaponStats.HeavyStateReleasePadding, settings.StateReleasePadding))
	local hitboxFallbackDelay = math.max(0.02, M1Calc.ToNumber(weaponStats.HeavyHitboxFallbackDelay, settings.HitboxFallbackDelay))
	local hitboxSize = weaponStats.HeavyHitboxSize
	local hitboxOffset = weaponStats.HeavyHitboxOffset

	-- Locks the attack (cooldown + Swing/Attacking state) and returns a safety token.
	local token, startErr = service:StartAttack(context, {
		actionName = context.actionName,
		cooldownDuration = cooldownDuration,
		attackWalkSpeed = attackWalkSpeed,
	})
	if not token then
		return false, startErr
	end

	service:PlayWeaponSound(character, equippedTool.Name, { "criticalcharge" }, rootPart)
	service:ReplicateWeaponaryEffect(
		"Indication",
		CombatNet.MakeIndicatorPayload(character, "yellow"),
		{ character },
		{ player }
	)

	local criticalAnimation = service:ResolveActionAnimation(character, equippedTool.Name, context.actionName, comboForReaction)
	local hitTriggered = false
	local releaseScheduled = false
	local hasTrack = false
	local interruptedBeforeHit = false

	local disconnectInterruptConns = function() end

	-- Releases the attack state once (prevents double release).
	local function scheduleRelease(delaySeconds: number)
		if releaseScheduled then
			return
		end
		releaseScheduled = true
		disconnectInterruptConns()
		service:ScheduleFinish(player, character, humanoid, token, delaySeconds)
	end

	local function markInterrupted()
		if interruptedBeforeHit then
			return
		end
		interruptedBeforeHit = true
		scheduleRelease(0)
	end

	disconnectInterruptConns = ActionUtil.BindInterruptSignals(character, humanoid, markInterrupted)

	-- Runs on the "hit" frame: checks token, replicates client VFX, applies push + hitbox.
	local function triggerHit()
		if hitTriggered then
			return
		end
		if not service:IsAttackTokenCurrent(player, token) then
			return
		end
		if not character or not character.Parent then
			return
		end

		hitTriggered = true
		character:SetAttribute("Attacking", false)

		if interruptedBeforeHit then
			return
		end

		if character:GetAttribute("Parrying") == true
			or character:GetAttribute("isBlocking") == true
			or character:GetAttribute("AutoParryActive") == true
		then
			-- If a defense is active at hit frame time, the strike is cancelled.
			return
		end

		service:ReplicateWeaponaryEffect(
			"Critical",
			CombatNet.MakeWeaponaryActionPayload(character, "Hit"),
			{ character },
			{ player }
		)

		service:PushForward(character, forwardSpeed, forwardDuration)
		service:PlayWeaponSound(character, equippedTool.Name, { "critical", "FlashStrike2" }, rootPart)
		service:SpawnHitbox({
			player = player,
			character = character,
			rootPart = rootPart,
			weaponStats = weaponStats,
			attackerToolName = equippedTool.Name,
			damage = damage,
			hitboxSize = hitboxSize,
			hitboxOffset = hitboxOffset,
			activeTime = M1Calc.ToNumber(weaponStats.HeavyHitboxActiveTime, settings.HitboxActiveTime),
			hitProfile = {
				knockbackStrength = knockbackStrength,
				stunDuration = stunDuration,
				ragdoll = ragdoll,
				ragdollDuration = ragdollDuration,
				comboForReaction = comboForReaction,
				guardBreakOnBlock = true,
			},
		})
	end

	-- If an animation exists, hit is triggered from "hit"/"hitbox" keyframes.
	if criticalAnimation then
		local track = service.AnimUtil.LoadTrack(humanoid, criticalAnimation, "CriticalAttack")
		if track then
			hasTrack = true
			track.Priority = settings.AttackTrackPriority
			track:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
			track:AdjustSpeed(swingSpeed)

			local keyframeConn: RBXScriptConnection? = nil
			keyframeConn = track.KeyframeReached:Connect(function(keyframeName)
				local key = string.lower(tostring(keyframeName))
				if key == "hit" or key == "hitbox" then
					triggerHit()
				end
			end)

			track.Stopped:Connect(function()
				if keyframeConn and keyframeConn.Connected then
					keyframeConn:Disconnect()
				end

				if not hitTriggered then
					triggerHit()
				end
				scheduleRelease(stateReleasePadding)
			end)
		end
	end

	-- Fallback: if no track is playable, still trigger hit after a short delay.
	if not hasTrack then
		task.delay(hitboxFallbackDelay, function()
			triggerHit()
			scheduleRelease(stateReleasePadding)
		end)
	end

	return true
end

return table.freeze(module)
