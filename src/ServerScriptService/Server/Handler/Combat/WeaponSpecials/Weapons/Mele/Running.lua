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
	local actionName = context.actionName or "Running"

	local comboForReaction = math.max(1, math.floor(M1Calc.ToNumber(weaponStats.RunningComboForReaction, 4)))
	local damage = M1Calc.ResolveDamage(player, weaponStats.RunningDamage or weaponStats.HeavyDamage or weaponStats.Damage or 8)
	local knockbackStrength = math.max(0, M1Calc.ToNumber(weaponStats.RunningKB, 28))
	local stunDuration = math.max(0, M1Calc.ToNumber(weaponStats.RunningStun, weaponStats.HeavyStun or 0.7))
	local ragdoll = weaponStats.RunningRagDoll == true
	local ragdollDuration = math.max(0, M1Calc.ToNumber(weaponStats.RunningRagDuration, weaponStats.HeavyRagDuration or 0))
	local cooldownDuration = math.max(0, M1Calc.ToNumber(weaponStats.RunningCooldown, settings.DefaultCooldown))
	local attackWalkSpeed = math.max(0, M1Calc.ToNumber(weaponStats.RunningWalkSpeed, settings.AttackWalkSpeed))
	local swingSpeed = math.max(0.01, M1Calc.ToNumber(weaponStats.RunningSwingSpeed, 1.2))
	local stateReleasePadding = math.max(0, M1Calc.ToNumber(weaponStats.RunningStateReleasePadding, settings.StateReleasePadding))
	local hitboxFallbackDelay = math.max(0.02, M1Calc.ToNumber(weaponStats.RunningHitboxFallbackDelay, settings.HitboxFallbackDelay))
	local hitboxSize = weaponStats.RunningHitboxSize
	local hitboxOffset = weaponStats.RunningHitboxOffset
	local windUpSpeed = M1Calc.ToNumber(weaponStats.RunningWindUpSpeed, 40)
	local windUpDuration = math.max(
		0.02,
		M1Calc.ToNumber(weaponStats.RunningWindUpDuration, weaponStats.HeavyForwardTime or weaponStats.RunningForwardTime or 0.1)
	)
	local windUpMaxForce = math.max(1200, M1Calc.ToNumber(weaponStats.RunningWindUpMaxForce, 14000))

	local token, startErr = service:StartAttack(context, {
		actionName = actionName,
		cooldownDuration = cooldownDuration,
		attackWalkSpeed = attackWalkSpeed,
	})
	if not token then
		return false, startErr
	end

	local trails = ActionUtil.CollectWeaponTrails(character, equippedTool)
	ActionUtil.SetTrailsEnabled(trails, false)

	service:PlayWeaponSound(character, equippedTool.Name, { "criticalcharge", "Runcritical" }, rootPart)
	service:ReplicateWeaponaryEffect(
		"Indication",
		CombatNet.MakeIndicatorPayload(character, "red"),
		{ character },
		{ player }
	)

	local function applyWindupImpulse()
		local flatDirection = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		if flatDirection.Magnitude <= 0 then
			return
		end

		service:PushVelocity(character, flatDirection.Unit * windUpSpeed, windUpDuration, windUpMaxForce)
	end

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

		service:SpawnHitbox({
			player = player,
			character = character,
			rootPart = rootPart,
			weaponStats = weaponStats,
			attackerToolName = equippedTool.Name,
			damage = damage,
			hitboxSize = hitboxSize,
			hitboxOffset = hitboxOffset,
			activeTime = M1Calc.ToNumber(weaponStats.RunningHitboxActiveTime, settings.HitboxActiveTime),
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
		local track = service.AnimUtil.LoadTrack(humanoid, attackAnimation, "RunningAttack")
		if track then
			hasTrack = true
			track.Looped = false
			track.Priority = settings.AttackTrackPriority
			track:Play(M1Calc.ToNumber(settings.AttackTrackFadeTime, 0.04))
			track:AdjustSpeed(swingSpeed)

			local keyframeConn: RBXScriptConnection? = nil
			keyframeConn = track.KeyframeReached:Connect(function(keyframeName)
				local ok, err = xpcall(function()
					local key = string.lower(tostring(keyframeName))

					if key == "startwindup" then
						applyWindupImpulse()
						ActionUtil.SetTrailsEnabled(trails, true)
					elseif key == "endwindup" then
						local swingName = math.random(1, 2) == 1 and "swing1" or "swing2"
						service:PlayWeaponSound(character, equippedTool.Name, { swingName }, rootPart)
					elseif key == "hitbox" or key == "hit" then
						triggerHit()
					elseif key == "end" then
						ActionUtil.SetTrailsEnabled(trails, false)
					end
				end, debug.traceback)

				if not ok then
					warn(("[WeaponSpecials][Mele][Running][%s] Keyframe error: %s"):format(player.Name, tostring(err)))
					scheduleRelease(0)
				end
			end)

			track.Stopped:Connect(function()
				local ok, err = xpcall(function()
					if keyframeConn and keyframeConn.Connected then
						keyframeConn:Disconnect()
					end

					if not hitTriggered then
						triggerHit()
					end
					scheduleRelease(stateReleasePadding)
				end, debug.traceback)

				if not ok then
					warn(("[WeaponSpecials][Mele][Running][%s] Track stop error: %s"):format(player.Name, tostring(err)))
					scheduleRelease(0)
				end
			end)

			local noKeyframeFallbackDelay = math.max(
				hitboxFallbackDelay,
				M1Calc.ToNumber(weaponStats.RunningNoKeyframeFallbackDelay, 0.45)
			)
			task.delay(noKeyframeFallbackDelay, function()
				if not service:IsAttackTokenCurrent(player, token) then
					return
				end
				if hitTriggered then
					return
				end

				triggerHit()
				scheduleRelease(stateReleasePadding)
			end)
		end
	end

	if not hasTrack then
		task.delay(hitboxFallbackDelay, function()
			local ok, err = xpcall(function()
				triggerHit()
				scheduleRelease(stateReleasePadding)
			end, debug.traceback)

			if not ok then
				warn(("[WeaponSpecials][Mele][Running][%s] Fallback error: %s"):format(player.Name, tostring(err)))
				scheduleRelease(0)
			end
		end)
	end

	local failsafeDelay = math.max(1.5, M1Calc.ToNumber(weaponStats.RunningFailsafeRelease, 2.8))
	task.delay(failsafeDelay, function()
		if service:IsAttackTokenCurrent(player, token) then
			scheduleRelease(0)
		end
	end)

	return true
end

return table.freeze(module)
