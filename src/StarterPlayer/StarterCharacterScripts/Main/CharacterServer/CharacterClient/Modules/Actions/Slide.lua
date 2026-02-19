local ActionsSlide = {}

function ActionsSlide.Bind(module, context)
	local StateManager = context.StateManager
	local Settings = context.Settings
	local RunService = context.RunService
	local StarterPlayer = context.StarterPlayer
	local AnimsHandler = context.AnimsHandler
	local Global = context.Global
	local destroyAfter = context.destroyAfter
	local isCarryOrGripBlocked = context.isCarryOrGripBlocked
	local createLinearVelocity = context.createLinearVelocity
	local createAlignOrientation = context.createAlignOrientation
	local playMoveAnim = context.playMoveAnim
	local slideParams = context.slideParams
	local slideConnManager = context.slideConnManager
	local slideVelocity = context.slideVelocity
	local slideAlign = context.slideAlign
	local slidePushLock = context.slidePushLock
	local crouchConnManager = context.crouchConnManager
	local scriptRef = context.script
	local sounds = scriptRef.Parent.Parent.Sounds

	local function isDefenseActive(plr: Player, char: Model): boolean
		if char:GetAttribute("isBlocking") == true or char:GetAttribute("Parrying") == true then
			return true
		end

		return StateManager.GetState(plr, "isBlocking") == true or StateManager.GetState(plr, "Parrying") == true
	end

	local function stopSlideConn(plr: Player)
		slideConnManager:Disconnect(plr)
	end

	local function refreshSlideFilter(char: Model)
		slideParams.FilterDescendantsInstances = { char }
	end

	local function getBaseWalkSpeed(plr: Player): number
		return (StateManager.GetState(plr, "Running") == true) and (Settings.Run.Extra or 22) or (Settings.Run.Normal or 8)
	end

	local function getGroundInfo(char: Model, hrp: BasePart, dist: number?)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char }
		rp.IgnoreWater = true

		local d = dist or 8
		local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -d, 0), rp)
		if not hit then
			return nil, nil
		end
		return hit.Instance.Color, hit.Normal
	end

	function module.SlidePush(plr: Player): boolean
		local char = plr.Character
		if not char then
			return false
		end
		if isCarryOrGripBlocked(plr) then
			return false
		end
		if isDefenseActive(plr, char) then
			return false
		end
		if StateManager.GetState(plr, "Sliding") ~= true then
			return false
		end
		if slidePushLock[plr] then
			return false
		end
		if StateManager.GetState(plr, "Vaulting") == true then
			return false
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			return false
		end

		slidePushLock[plr] = true
		StateManager.SetState(plr, "slidePush", true, 0, true)

		local v = hrp.AssemblyLinearVelocity
		local horizSpeed = Vector3.new(v.X, 0, v.Z).Magnitude

		local cfg = Settings.Sliding or {}
		local pushCfg = cfg.PushVelocity or {}
		local up = pushCfg.Up or 35

		local baseSpeed = cfg.BaseSpeed or 55
		local maxMult = cfg.MaxMultiplier or 1.5
		local maxSlideSpeed = baseSpeed * maxMult
		local t = math.clamp(horizSpeed / maxSlideSpeed, 0, 1) + 0.15

		local groundColor, groundNormal = getGroundInfo(char, hrp, 8)

		if t >= 0.86 then
			Global.SlideJump({ char, { "HumanoidRootPart", groundColor, true, groundNormal } })
		else
			Global.SlideJump2({ char, { groundColor, groundNormal } })
		end

		local minForward = pushCfg.MinForward or 25
		local maxForward = pushCfg.MaxForward or 85
		local forward = minForward + (maxForward - minForward) * t

		module.SlideStop(plr)

		local bv = createLinearVelocity(hrp, "SlidePush", Vector3.new(math.huge, math.huge, math.huge))
		bv.VectorVelocity = (hrp.CFrame.LookVector * forward) + Vector3.new(0, up, 0)
		destroyAfter(bv, 0.12)

		task.delay(0.15, function()
			slidePushLock[plr] = nil
			StateManager.SetState(plr, "slidePush", false, 0, true)
		end)

		return true
	end

	function module.SlideStop(plr: Player)
		local char = plr.Character
		if not char then
			return
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			return
		end

		StateManager.SetState(plr, "Sliding", false, 0, true)
		stopSlideConn(plr)

		local bv = slideVelocity[plr]
		if bv and bv.Parent then
			bv:Destroy()
		end
		slideVelocity[plr] = nil

		local align = slideAlign[plr]
		if align and align.Parent then
			align:Destroy()
		end
		slideAlign[plr] = nil

		AnimsHandler.StopAnims(char, "Slide")

		sounds.Slide:Stop()
		Global.Slide({ char, { "Torso", nil, false } })
		Global.FOV({ nil, { 0.1, 70 } })

		if Settings.Sliding and Settings.Sliding.HipHeight then
			humanoid.HipHeight = Settings.Sliding.HipHeight.Normal
		end
		humanoid.WalkSpeed = getBaseWalkSpeed(plr)

		local cd = (Settings.Sliding and Settings.Sliding.Cooldown) or 0.8
		StateManager.SetState(plr, "SlideLock", true, cd, true)
	end

	function module.SlideStart(plr: Player): boolean
		local char = plr.Character
		if not char then
			return false
		end
		if isCarryOrGripBlocked(plr) then
			return false
		end
		if isDefenseActive(plr, char) then
			return false
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			return false
		end

		if StateManager.GetState(plr, "SlideLock") == true then
			return false
		end
		if StateManager.GetState(plr, "Sliding") == true then
			return false
		end
		if humanoid.FloorMaterial == Enum.Material.Air then
			return false
		end
		if StateManager.GetState(plr, "Vaulting") == true then
			return false
		end
		if StateManager.GetState(plr, "Climbing") == true then
			return false
		end
		if StateManager.GetState(plr, "WallRunning") == true then
			return false
		end
		if StateManager.GetState(plr, "Stunned") == true then
			return false
		end

		refreshSlideFilter(char)

		local rayDir = -hrp.CFrame.UpVector * 5
		local groundRay = workspace:Raycast(hrp.Position, rayDir, slideParams)
		if not groundRay then
			return false
		end

		StateManager.SetState(plr, "Sliding", true, 0, true)

		Global.BodyTrail({ char, 1, "BodyTrail1" })
		Global.FOV({ nil, { 0.1, 80 } })

		sounds.Slide:Play()

		local partBelow = workspace:Raycast(hrp.Position, hrp.CFrame.UpVector * -5, slideParams)
		local lastSlideColor: Color3? = nil
		if partBelow then
			Global.Slide({ char, { "Torso", partBelow.Instance.Color, true } })
			lastSlideColor = partBelow.Instance.Color
		else
			Global.Slide({ char, { "Torso", nil, true } })
		end

		if Settings.Sliding and Settings.Sliding.HipHeight then
			humanoid.HipHeight = Settings.Sliding.HipHeight.Slide
		end

		local slideTrack = playMoveAnim(char, "Slide", "Slide")
		if slideTrack then
			slideTrack:Play(0.15)
		end

		local bv = createLinearVelocity(hrp, "SlideVelocity", Vector3.new(40000, 0, 40000))
		bv.VectorVelocity = hrp.CFrame.LookVector * ((Settings.Sliding and Settings.Sliding.BaseSpeed) or 40)
		slideVelocity[plr] = bv

		local align = createAlignOrientation(hrp, "SlideAlign", 100)
		slideAlign[plr] = align

		local prevY: number? = nil
		local mult = 1
		local baseVol = 0.5

		slideConnManager:Set(plr, RunService.Heartbeat:Connect(function(dt)
			if not char.Parent or humanoid.Health <= 0 then
				module.SlideStop(plr)
				return
			end

			local gRay = workspace:Raycast(hrp.Position, -hrp.CFrame.UpVector * 10, slideParams)
			if not gRay then
				module.SlideStop(plr)
				return
			end

			if gRay.Instance and gRay.Instance.Color ~= lastSlideColor then
				lastSlideColor = gRay.Instance.Color
				Global.Slide({ char, { "Torso", lastSlideColor, true } })
			end

			local curY = hrp.Position.Y
			if prevY == nil then
				prevY = curY
			end

			local dy = curY - prevY
			prevY = curY

			local right = hrp.CFrame.RightVector
			local up = gRay.Normal
			local face = right:Cross(up)
			align.CFrame = CFrame.fromMatrix(hrp.Position, right, up, face)

			local baseSpeed = (Settings.Sliding and Settings.Sliding.BaseSpeed) or 55
			bv.VectorVelocity = hrp.CFrame.LookVector * (baseSpeed * mult)

			local rates = (Settings.Sliding and Settings.Sliding.SpeedChangeRate)
				or { Forward = 1, Upward = 2, Downward = 1 }

			if math.abs(dy) < 0.1 then
				if mult > 1 then
					mult = math.clamp(
						mult - ((rates.Forward or 1) * 2) * dt,
						0,
						(Settings.Sliding and Settings.Sliding.MaxMultiplier) or 2
					)
				end
				mult = math.clamp(
					mult - (rates.Forward or 1) * dt,
					0,
					(Settings.Sliding and Settings.Sliding.MaxMultiplier) or 2
				)
			elseif dy > 0 then
				if mult > 1 then
					mult = math.clamp(
						mult - ((rates.Upward or 2) * 2) * dt,
						0,
						(Settings.Sliding and Settings.Sliding.MaxMultiplier) or 2
					)
				end
				mult = math.clamp(
					mult - (rates.Upward or 2) * dt,
					0,
					(Settings.Sliding and Settings.Sliding.MaxMultiplier) or 2
				)
			else
				mult = math.clamp(
					mult + (rates.Downward or 1) * dt,
					0,
					(Settings.Sliding and Settings.Sliding.MaxMultiplier) or 2
				)
			end

			sounds.Slide.Volume = baseVol * mult

			if mult < 0.1 then
				module.SlideStop(plr)
			end
		end))

		return true
	end

	local function stopCrouchConn(plr: Player)
		crouchConnManager:Disconnect(plr)
	end

	function module.CrouchToggle(action: "Play" | "Stop", plr: Player): boolean
		local char = plr.Character
		if not char then
			return false
		end
		if action == "Play" and isCarryOrGripBlocked(plr) then
			return false
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return false
		end

		if action == "Play" then
			if StateManager.GetState(plr, "Crouching") == true then
				return false
			end
			if isDefenseActive(plr, char) then
				return false
			end
			if StateManager.GetState(plr, "Sliding") == true then
				return false
			end
			if StateManager.GetState(plr, "Vaulting") == true then
				return false
			end
			if StateManager.GetState(plr, "Climbing") == true then
				return false
			end
			if StateManager.GetState(plr, "WallRunning") == true then
				return false
			end
			if StateManager.GetState(plr, "Dashing") == true then
				return false
			end
			if StateManager.GetState(plr, "Stunned") == true then
				return false
			end
			if humanoid.Health <= 0 then
				return false
			end

			StateManager.SetState(plr, "Crouching", true, 0, true)

			AnimsHandler.StopAnims(char, "Crouch")
			local crouchTrack = playMoveAnim(char, "Crouch", "Crouch")
			if crouchTrack then
				crouchTrack:Play(0.1)
			end

			humanoid.WalkSpeed = (Settings.Run.Normal / 2)

			crouchConnManager:Set(plr, RunService.Heartbeat:Connect(function()
				if not char.Parent or humanoid.Health <= 0 then
					module.CrouchToggle("Stop", plr)
					return
				end

				local moving = humanoid.MoveDirection.Magnitude > 0
				local bucket = AnimsHandler.GetAnims(char, "Crouch")
				if bucket then
					for _, entry in pairs(bucket) do
						local t = entry and entry.Track
						if t and t.IsPlaying then
							t:AdjustSpeed(moving and 1 or 0)
							break
						end
					end
				end
			end))

			return true
		end

		if StateManager.GetState(plr, "Crouching") ~= true then
			stopCrouchConn(plr)
			return false
		end

		stopCrouchConn(plr)

		AnimsHandler.StopAnims(char, "Crouch")
		StateManager.SetState(plr, "Crouching", false, 0, true)

		local base = (StateManager.GetState(plr, "Running") == true) and Settings.Run.Extra or Settings.Run.Normal
		humanoid.WalkSpeed = base
		humanoid.JumpPower = StarterPlayer.CharacterJumpPower

		local cd = (Settings.Crouch and Settings.Crouch.Cooldown)
			or (Settings.Sliding and Settings.Sliding.Cooldown)
			or 0.5
		StateManager.SetState(plr, "CrouchLock", true, cd, true)

		return true
	end

	function module.CleanupSlideState(plr: Player)
		stopSlideConn(plr)
		stopCrouchConn(plr)

		local bv = slideVelocity[plr]
		if bv and bv.Parent then
			bv:Destroy()
		end
		slideVelocity[plr] = nil

		local align = slideAlign[plr]
		if align and align.Parent then
			align:Destroy()
		end
		slideAlign[plr] = nil

		slidePushLock[plr] = nil
	end
end

return ActionsSlide
