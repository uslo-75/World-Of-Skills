local ActionsFall = {}

function ActionsFall.Bind(module, context)
	local StateManager = context.StateManager
	local MoveFolder = context.MoveFolder
	local StarterPlayer = context.StarterPlayer
	local AnimsHandler = context.AnimsHandler
	local Global = context.Global
	local rockDebris = context.rockDebris
	local restoreMovement = context.restoreMovement
	local getFallBucket = context.getFallBucket
	local refreshParams = context.refreshParams
	local fallParams = context.fallParams
	local landingLock = context.landingLock

	function module.UpdateFall(plr: Player, char: Model, humanoid: Humanoid, hrp: BasePart, _dt: number)
		refreshParams(fallParams, char)

		local playClimb = StateManager.GetState(plr, "PlayClimb") == true
		local falling = StateManager.GetState(plr, "Falling") == true

		local bucket = getFallBucket(char)
		local vy = hrp.AssemblyLinearVelocity.Y

		if playClimb or char:GetAttribute("FallDamageCD") then
			if falling then
				bucket.fallMag = 0
				StateManager.SetState(plr, "Falling", false, 0, true)
			end
			return
		end

		if not falling then
			if vy < -40 then
				bucket.oldY = hrp.Position.Y
				bucket.fallMag = 0
				StateManager.SetState(plr, "Falling", true, 0, true)
			end
			return
		end

		local newY = hrp.Position.Y
		local diff = newY - bucket.oldY
		if diff <= 0 then
			bucket.fallMag -= diff
		end
		bucket.oldY = newY

		local ray = workspace:Raycast(hrp.Position, Vector3.new(0, -4, 0), fallParams)
		if not ((vy > -2) and ray and ray.Instance) then
			return
		end

		StateManager.SetState(plr, "Falling", false, 0, true)

		local fallMag = bucket.fallMag
		bucket.fallMag = 0

		if fallMag < 4 then
			return
		end

		local groundPart = ray.Instance
		local fallColor = groundPart.Color
		local groundMaterial = groundPart.Material

		landingLock[char] = true

		local function playLandingAnimAndMaybeResumeRun()
			local landAnim = MoveFolder:FindFirstChild("Landing") or MoveFolder:FindFirstChild("Landed")
			if landAnim and landAnim:IsA("Animation") then
				local landTrack = AnimsHandler.LoadAnim(char, "Landed", landAnim.AnimationId, nil, { replaceType = true })
				if landTrack then
					landTrack.Name = "Landed"
					landTrack.Stopped:Once(function()
						landingLock[char] = nil
						if StateManager.GetState(plr, "Running") == true then
							module.Running("Play", plr, nil)
						end
					end)
					return
				end
			end

			landingLock[char] = nil
			if StateManager.GetState(plr, "Running") == true then
				module.Running("Play", plr, nil)
			end
		end

		if fallMag < 10 then
			playLandingAnimAndMaybeResumeRun()

			Global.FOV({ nil, { 0.10, 66 } })
			task.delay(0.12, function()
				Global.FOV({ nil, { 0.12, 70 } })
			end)
			Global.Fall({ char, fallColor })
			char.HumanoidRootPart.Landing:Play()

			humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed / 3
			humanoid.JumpPower = 0

			task.delay(0.55, function()
				if char.Parent and humanoid.Parent then
					restoreMovement(plr, humanoid)
				end
			end)

			return
		end

		local dmg = ((fallMag - 20) * 1.5) * 0.95
		if dmg < 2 or char:GetAttribute("NoFall") then
			landingLock[char] = nil
			if StateManager.GetState(plr, "Running") == true then
				module.Running("Play", plr, nil)
			end
			return
		end

		rockDebris(hrp, math.random(1, 2), fallColor, groundMaterial, true)
		playLandingAnimAndMaybeResumeRun()

		Global.FOV({ nil, { 0.10, 64 } })
		task.delay(0.10, function()
			Global.FOV({ nil, { 0.12, 70 } })
		end)
		Global.BodyColour({ char, { 0.25, Color3.fromRGB(255, 102, 102) } })
		Global.Fall({ char, fallColor })

		char:SetAttribute("FallDamageCD", true)
		task.delay(0.22, function()
			if char and char.Parent then
				char:SetAttribute("FallDamageCD", nil)
			end
		end)

		humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed / 3
		humanoid.JumpPower = 0

		task.delay(0.75, function()
			if char.Parent and humanoid.Parent then
				restoreMovement(plr, humanoid)
			end
		end)
	end
end

return ActionsFall
