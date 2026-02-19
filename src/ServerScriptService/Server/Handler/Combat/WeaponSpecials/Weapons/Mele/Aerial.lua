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
	local actionName = context.actionName or "Aerial"

	local comboForReaction = math.max(1, math.floor(M1Calc.ToNumber(weaponStats.AerialComboForReaction, 4)))
	local damage = M1Calc.ResolveDamage(player, weaponStats.AerialDamage or weaponStats.HeavyDamage or weaponStats.Damage or 8)
	local knockbackStrength = math.max(0, M1Calc.ToNumber(weaponStats.AerialKB, 15))
	local stunDuration = math.max(0, M1Calc.ToNumber(weaponStats.AerialStun, weaponStats.HeavyStun or 0.65))
	local ragdoll = weaponStats.AerialRagDoll == true
	local ragdollDuration = math.max(0, M1Calc.ToNumber(weaponStats.AerialRagDuration, weaponStats.HeavyRagDuration or 0))
	local cooldownDuration = math.max(0, M1Calc.ToNumber(weaponStats.AerialCooldown, settings.DefaultCooldown))
	local attackWalkSpeed = math.max(0, M1Calc.ToNumber(weaponStats.AerialWalkSpeed, settings.AttackWalkSpeed))
	local swingSpeed = math.max(0.01, M1Calc.ToNumber(weaponStats.AerialSwingSpeed, 1.1))
	local downSwingSpeed = math.max(0.01, M1Calc.ToNumber(weaponStats.AerialDownSwingSpeed, 1.3))
	local stateReleasePadding = math.max(0, M1Calc.ToNumber(weaponStats.AerialStateReleasePadding, settings.StateReleasePadding))
	local hitboxFallbackDelay = math.max(0.02, M1Calc.ToNumber(weaponStats.AerialHitboxFallbackDelay, settings.HitboxFallbackDelay))
	local hitboxSize = weaponStats.AerialHitboxSize
	local hitboxOffset = weaponStats.AerialHitboxOffset
	local liftForwardSpeed = M1Calc.ToNumber(weaponStats.AerialLiftForwardSpeed, 30)
	local liftUpSpeed = M1Calc.ToNumber(weaponStats.AerialLiftUpSpeed, 15)
	local liftDuration = math.max(0.02, M1Calc.ToNumber(weaponStats.AerialLiftDuration, 0.15))
	local liftMaxForce = math.max(1200, M1Calc.ToNumber(weaponStats.AerialLiftMaxForce, 120000))
	local downForwardSpeed = M1Calc.ToNumber(weaponStats.AerialDownForwardSpeed, 40)
	local downVerticalSpeed = M1Calc.ToNumber(weaponStats.AerialDownVerticalSpeed, -33)
	local downDuration = math.max(0.02, M1Calc.ToNumber(weaponStats.AerialDownDuration, 0.2))
	local downMaxForce = math.max(1200, M1Calc.ToNumber(weaponStats.AerialDownMaxForce, 150000))

	local token, startErr = service:StartAttack(context, {
		actionName = actionName,
		cooldownDuration = cooldownDuration,
		attackWalkSpeed = attackWalkSpeed,
	})
	if not token then
		return false, startErr
	end

	local trails = ActionUtil.CollectWeaponTrails(character, equippedTool)
	ActionUtil.SetTrailsEnabled(trails, true)

	service:PlayWeaponSound(character, equippedTool.Name, { "whirlwind1" }, rootPart)
	service:ReplicateWeaponaryEffect(
		"Indication",
		CombatNet.MakeIndicatorPayload(character, "red"),
		{ character },
		{ player }
	)

	local function replicateAerialVfx(stage: string)
		service:ReplicateWeaponaryEffect(
			actionName,
			CombatNet.MakeWeaponaryActionPayload(character, stage),
			{ character },
			{ player }
		)
	end

	local function applyLiftImpulse()
		local velocity = rootPart.CFrame.LookVector * liftForwardSpeed + Vector3.new(0, liftUpSpeed, 0)
		service:PushVelocity(character, velocity, liftDuration, liftMaxForce)
	end

	local function applyDownImpulse()
		local velocity = rootPart.CFrame.LookVector * downForwardSpeed + Vector3.new(0, downVerticalSpeed, 0)
		service:PushVelocity(character, velocity, downDuration, downMaxForce)
	end

	applyLiftImpulse()
	service:PlayWeaponSound(character, equippedTool.Name, { "Aircritical" }, rootPart)

	local attackAnimation = service:ResolveActionAnimation(character, equippedTool.Name, actionName, comboForReaction)
	local hitTriggered = false
	local releaseScheduled = false
	local hasTrack = false
	local interruptedBeforeHit = false
	local disconnectInterruptConns = function() end

	local function scheduleRelease(delaySeconds: number)
		if releaseScheduled then
			return
		end
		releaseScheduled = true
		disconnectInterruptConns()
		ActionUtil.SetTrailsEnabled(trails, false)
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
			return
		end

		replicateAerialVfx("Hit")
		service:SpawnHitbox({
			player = player,
			character = character,
			rootPart = rootPart,
			weaponStats = weaponStats,
			attackerToolName = equippedTool.Name,
			damage = damage,
			hitboxSize = hitboxSize,
			hitboxOffset = hitboxOffset,
			activeTime = M1Calc.ToNumber(weaponStats.AerialHitboxActiveTime, settings.HitboxActiveTime),
			hitProfile = {
				knockbackStrength = knockbackStrength,
				stunDuration = stunDuration,
				ragdoll = ragdoll,
				ragdollDuration = ragdollDuration,
				comboForReaction = comboForReaction,
				guardBreakOnBlock = false,
			},
		})
	end

	if attackAnimation then
		local track = service.AnimUtil.LoadTrack(humanoid, attackAnimation, "AerialAttack")
		if track then
			hasTrack = true
			track.Priority = settings.AttackTrackPriority
			track:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
			track:AdjustSpeed(swingSpeed)

			local keyframeConn: RBXScriptConnection? = nil
			keyframeConn = track.KeyframeReached:Connect(function(keyframeName)
				local key = string.lower(tostring(keyframeName))
				if key == "air" then
					replicateAerialVfx("Air")
				elseif key == "down" then
					track:AdjustSpeed(downSwingSpeed)
					replicateAerialVfx("Down")
					applyDownImpulse()
					service:PlayWeaponSound(character, equippedTool.Name, { "StaticFlourish1" }, rootPart)
				elseif key == "hit" or key == "hitbox" then
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

	if not hasTrack then
		task.delay(hitboxFallbackDelay, function()
			triggerHit()
			scheduleRelease(stateReleasePadding)
		end)
	end

	return true
end

return table.freeze(module)
