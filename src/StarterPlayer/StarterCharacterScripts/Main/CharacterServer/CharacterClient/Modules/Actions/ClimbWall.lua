local ActionsClimbWall = {}

function ActionsClimbWall.Bind(module, context)
	local StateManager = context.StateManager
	local Settings = context.Settings
	local RunService = context.RunService
	local Global = context.Global
	local sounds = context.sounds
	local AnimsHandler = context.AnimsHandler
	local createLinearVelocity = context.createLinearVelocity
	local createAlignOrientation = context.createAlignOrientation
	local playMoveAnim = context.playMoveAnim
	local refreshParams = context.refreshParams
	local vaultParams = context.vaultParams
	local vaultRayCheckForClimb = context.vaultRayCheckForClimb
	local lerp = context.lerp
	local isCarryOrGripBlocked = context.isCarryOrGripBlocked
	local isGripBlocked = context.isGripBlocked
	local climbConnManager = context.climbConnManager
	local wallRunConnManager = context.wallRunConnManager
	local destroyAfter = context.destroyAfter

	local function isDefenseActive(plr: Player, char: Model): boolean
		if char:GetAttribute("isBlocking") == true or char:GetAttribute("Parrying") == true then
			return true
		end

		return StateManager.GetState(plr, "isBlocking") == true or StateManager.GetState(plr, "Parrying") == true
	end

	local function stopClimbConn(plr: Player)
		climbConnManager:Disconnect(plr)
	end

	local function movementClimbJumpOff(plr: Player)
		local char = plr.Character
		if not char then
			return
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			return
		end

		task.wait(0.2)

		StateManager.SetState(plr, "ClimbUp", true, 0, true)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

		local bodyVel = createLinearVelocity(hrp, "ClimbingDisengage", Vector3.new(15000, 15000, 15000))
		bodyVel.VectorVelocity = Vector3.new(0, 0, 0)

		local currentTime = 0
		local power = (Settings.DoubleJump and Settings.DoubleJump.Power) or 50
		local decay = (Settings.DoubleJump and Settings.DoubleJump.Decay) or 1

		local t = playMoveAnim(char, "ClimbJumpOff", "ClimbJumpOff")
		if t then
			t:AdjustSpeed(2.5)
		end

		sounds.WallKick:Play()

		Global.FOV({ nil, { 0.1, 75 } })
		task.wait(0.1)
		Global.FOV({ nil, { 0.1, 70 } })
		Global.BodyTrail({ char, 1, "BodyTrail1" })

		local jumpOffDir = hrp.CFrame.LookVector

		climbConnManager:Set(plr, RunService.Heartbeat:Connect(function(delta: number)
			currentTime += delta * decay

			local timePosition = math.clamp(1 - currentTime, 0, 1)
			local percentage = lerp(0, 1, timePosition)

			local v = power * percentage
			bodyVel.VectorVelocity = Vector3.yAxis * v - jumpOffDir * 15
		end))

		local function cleanup()
			if bodyVel.Parent then
				bodyVel:Destroy()
			end
			stopClimbConn(plr)
			StateManager.SetState(plr, "ClimbUp", false, 0, true)
		end

		if t then
			local len = t.Length
			local speed = t.Speed > 0 and t.Speed or 1

			task.delay((len * 0.45) / speed, cleanup)
		else
			task.delay(0.35, cleanup)
		end
	end

	function module.MovementClimb(plr: Player): boolean
		local char = plr.Character
		if not char then
			return false
		end
		if isDefenseActive(plr, char) then
			return false
		end
		if isGripBlocked(plr) then
			return false
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		local head: BasePart? = char:FindFirstChild("Head")
		local primary: BasePart? = char.PrimaryPart or hrp
		if not humanoid or not hrp or not head or not primary then
			return false
		end

		if humanoid.FloorMaterial ~= Enum.Material.Air then
			return false
		end
		if StateManager.GetState(plr, "Climbing") == true then
			return false
		end
		if StateManager.GetState(plr, "ClimbLock") == true then
			return false
		end

		AnimsHandler.StopAnims(char, "Landed")
		AnimsHandler.StopAnims(char, "Base")
		AnimsHandler.StopAnims(char, "Climb")
		AnimsHandler.StopAnims(char, "ClimbUp")
		AnimsHandler.StopAnims(char, "ClimbJumpOff")

		refreshParams(vaultParams, char)

		local firstResult = workspace:Raycast(hrp.CFrame.Position, hrp.CFrame.LookVector * 2, vaultParams)
		if not firstResult then
			return false
		end

		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0

		StateManager.SetState(plr, "Climbing", true, 0, true)
		StateManager.SetState(plr, "ClimbLock", true, 0, true)

		sounds.climb1:Play()

		local bodyVel = createLinearVelocity(hrp, "ClimbingVelocity", Vector3.new(0, 15000, 0))
		bodyVel.VectorVelocity = Vector3.new(0, 1, 0)

		local alignOrientation = createAlignOrientation(primary, "ClimbingAlign", 100)
		alignOrientation.CFrame = CFrame.lookAlong(primary.CFrame.Position, -firstResult.Normal)

		local climbTrack = playMoveAnim(char, "Climb", "Climb")
		task.delay(0.2, function()
			if char.Parent then
				sounds.climb2:Play()
			end
		end)

		local currentTime = 0
		local force = (Settings.Climb and Settings.Climb.Force) or 60
		local decay = (Settings.Climb and Settings.Climb.Decay) or 1

		local keyConn: RBXScriptConnection? = nil
		if climbTrack then
			keyConn = climbTrack.KeyframeReached:Connect(function(_keyframeName)
				currentTime = 0
				sounds.KickUp:Play()
			end)
		end

		local cleaned = false
		local function cleanup()
			if cleaned then
				return
			end
			cleaned = true

			stopClimbConn(plr)

			if keyConn then
				keyConn:Disconnect()
				keyConn = nil
			end

			if bodyVel.Parent then
				bodyVel:Destroy()
			end

			local function climbVaultProcedure()
				local upTrack = playMoveAnim(char, "ClimbUp", "ClimbUp")
				if upTrack then
					upTrack:AdjustSpeed(2.5)
				end
				StateManager.SetState(plr, "ClimbUp", true, 0, true)

				Global.BodyTrail({ char, 0.5, "BodyTrail1" })
				Global.FOV({ nil, { 0.25, 75 } })
				task.wait(0.25)
				Global.FOV({ nil, { 0.25, 70 } })

				sounds.Whoosh1.TimePosition = 0.2
				sounds.Whoosh1:Play()

				if upTrack then
					upTrack.Stopped:Once(function()
						StateManager.SetState(plr, "ClimbUp", false, 0, true)
					end)
				else
					task.delay(0.35, function()
						StateManager.SetState(plr, "ClimbUp", false, 0, true)
					end)
				end
			end

			if
				vaultRayCheckForClimb(char, hrp, 5)
				and not hrp:FindFirstChild("ClimbingDisengage")
				and not StateManager.GetState(plr, "ClimbDisengage")
			then
				climbVaultProcedure()

				task.spawn(function()
					if not hrp.Parent then
						return
					end
					local v = createLinearVelocity(hrp, "ClimbVaultVelocity", Vector3.new(15000, 15000, 15000))
					v.VectorVelocity = hrp.CFrame.LookVector * 15 + Vector3.new(0, 5, 0)
					destroyAfter(v, 0.15)
				end)
			elseif
				vaultRayCheckForClimb(char, head, 5)
				and not hrp:FindFirstChild("ClimbingDisengage")
				and not StateManager.GetState(plr, "ClimbDisengage")
			then
				climbVaultProcedure()

				task.spawn(function()
					if not hrp.Parent then
						return
					end
					local v = createLinearVelocity(hrp, "ClimbVaultVelocity", Vector3.new(15000, 15000, 15000))
					v.VectorVelocity = hrp.CFrame.LookVector * 15 + Vector3.new(0, 20, 0)
					destroyAfter(v, 0.15)
				end)
			end

			task.spawn(function()
				if humanoid and humanoid.Parent then
					humanoid.AutoRotate = true
				end
				if alignOrientation and alignOrientation.Parent then
					alignOrientation:Destroy()
				end
			end)

			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = (StateManager.GetState(plr, "Running") == true) and Settings.Run.Extra
					or Settings.Run.Normal
			end

			task.delay(0.15, function()
				StateManager.SetState(plr, "Climbing", false, 0, true)
			end)
		end

		climbConnManager:Set(plr, RunService.Heartbeat:Connect(function(delta: number)
			if not char.Parent or humanoid.Health <= 0 then
				return
			end

			humanoid:ChangeState(Enum.HumanoidStateType.Climbing)

			currentTime += delta * decay

			local timePosition = math.clamp(1 - currentTime, 0, 1)
			local percentage = lerp(0, 1, timePosition)

			bodyVel.VectorVelocity = Vector3.yAxis * (force * percentage)

			local result = workspace:Raycast(
				primary.CFrame.Position - Vector3.new(0, 2, 0),
				primary.CFrame.LookVector * 2.2,
				vaultParams
			)
			if result and result.Instance then
				alignOrientation.CFrame = CFrame.lookAlong(primary.Position, -result.Normal)
			else
				if climbTrack then
					climbTrack:Stop()
				end
			end

			if StateManager.GetState(plr, "ClimbDisengage") == true then
				if climbTrack then
					climbTrack:Stop()
				end

				task.defer(function()
					movementClimbJumpOff(plr)
					StateManager.SetState(plr, "ClimbDisengage", false, 0, true)
				end)
			end
		end))

		if climbTrack then
			climbTrack.Stopped:Once(cleanup)
		else
			task.delay(0.35, cleanup)
		end

		return true
	end

	function module.UpdateClimbLock(plr: Player, humanoid: Humanoid)
		if StateManager.GetState(plr, "ClimbLock") ~= true then
			return
		end

		if StateManager.GetState(plr, "Climbing") == true then
			return
		end
		if StateManager.GetState(plr, "ClimbHang") == true then
			return
		end
		if StateManager.GetState(plr, "Vaulting") == true then
			return
		end

		if humanoid.FloorMaterial ~= Enum.Material.Air then
			StateManager.SetState(plr, "ClimbLock", false, 0, true)
		end
	end

	local function stopWallRunConn(plr: Player)
		wallRunConnManager:Disconnect(plr)
	end

	function module.WallRunJumpOff(plr: Player, direction: number): boolean
		local char = plr.Character
		if not char then
			return false
		end
		if isDefenseActive(plr, char) then
			return false
		end
		if isCarryOrGripBlocked(plr) then
			return false
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			return false
		end

		if StateManager.GetState(plr, "WallHopping") == true then
			return false
		end

		StateManager.SetState(plr, "WallHopping", true, 0, true)

		local waitStart = time()
		while hrp:FindFirstChild("WallRunVelocity") do
			if time() - waitStart > 0.35 then
				break
			end
			task.wait()
		end

		local bodyVel = createLinearVelocity(hrp, "WallRunDisengage", Vector3.new(15000, 15000, 15000))
		bodyVel.VectorVelocity = Vector3.new(0, 0, 0)

		local hopDir: Vector3 = -hrp.CFrame.RightVector
		local track: AnimationTrack? = nil

		if direction == -1 then
			track = playMoveAnim(char, "WallHop", "WallHopLeft")
			if track then
				track:AdjustSpeed(2)
			end
			hopDir = hrp.CFrame.RightVector
		elseif direction == 1 then
			track = playMoveAnim(char, "WallHop", "WallHopRight")
			if track then
				track:AdjustSpeed(2)
			end
			hopDir = -hrp.CFrame.RightVector
		end

		task.spawn(function()
			Global.FOV({ nil, { 0.1, 75 } })
			task.wait(0.1)
			Global.FOV({ nil, { 0.1, 70 } })
		end)
		Global.BodyTrail({ char, 1, "BodyTrail1" })

		bodyVel.VectorVelocity = hopDir * 25 + Vector3.new(0, 20, 0) + (hrp.CFrame.LookVector * 30)

		local cleaned = false
		local function cleanup()
			if cleaned then
				return
			end
			cleaned = true
			if bodyVel.Parent then
				bodyVel:Destroy()
			end
			StateManager.SetState(plr, "WallHopping", false, 0, true)
		end

		if track then
			track.Stopped:Once(cleanup)
		else
			task.delay(0.35, cleanup)
		end

		return true
	end

	function module.WallRun(plr: Player, rayInput: RaycastResult, direction: number, wallRunParams: RaycastParams)
		local char = plr.Character
		if not char then
			return
		end
		if isDefenseActive(plr, char) then
			return
		end
		if isCarryOrGripBlocked(plr) then
			return
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			return
		end
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			return
		end

		if StateManager.GetState(plr, "WallRunning") == true then
			return
		end
		if StateManager.GetState(plr, "Vaulting") == true then
			return
		end
		if StateManager.GetState(plr, "Climbing") == true then
			return
		end
		if StateManager.GetState(plr, "Sliding") == true then
			return
		end
		if StateManager.GetState(plr, "Stunned") == true then
			return
		end

		local wallNormal = rayInput.Normal
		local wallDirection = wallNormal:Cross(Vector3.new(0, direction, 0))

		local bodyVel = createLinearVelocity(hrp, "WallRunVelocity", Vector3.new(14000, 14000, 14000))
		bodyVel.VectorVelocity = wallDirection * Settings.WallRun.wallRunSpeed

		local dirValue = Instance.new("IntValue")
		dirValue.Name = "Direction"
		dirValue.Value = direction
		dirValue.Parent = bodyVel

		local alignOrientation = createAlignOrientation(hrp, "WallRunAlign", 100)
		alignOrientation.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + wallNormal)

		local function updateOrientation(n: Vector3)
			local lookDir = (direction == 1) and n:Cross(Vector3.new(0, 1, 0)) or n:Cross(Vector3.new(0, -1, 0))
			alignOrientation.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir, Vector3.new(0, 1, 0))
		end

		local function resetOrientation()
			humanoid.AutoRotate = true
			if alignOrientation.Parent then
				alignOrientation:Destroy()
			end
		end

		local function destroyVel()
			resetOrientation()
			if bodyVel.Parent then
				bodyVel:Destroy()
			end
		end

		updateOrientation(wallNormal)

		destroyAfter(bodyVel, Settings.WallRun.wallRunDuration)
		destroyAfter(alignOrientation, Settings.WallRun.wallRunDuration)

		StateManager.SetState(plr, "WallRunning", true, 0, true)
		humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
		humanoid.AutoRotate = false

		local wallRunAnim = (direction == -1) and "WallRunLeft" or "WallRunRight"
		local t = playMoveAnim(char, "WallRun", wallRunAnim)
		if t then
			t:AdjustSpeed(1.3)
		end

		if direction == -1 then
			Global.WallRun({ char, { "Left Arm", true } })
		else
			Global.WallRun({ char, { "Right Arm", true } })
		end

		sounds.WallRun:Play()

		bodyVel.Destroying:Connect(function()
			stopWallRunConn(plr)

			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

			if direction == -1 then
				Global.WallRun({ char, { "Left Arm", false } })
			else
				Global.WallRun({ char, { "Right Arm", false } })
			end

			StateManager.SetState(plr, "WallRunning", false, 0, true)

			resetOrientation()
			if t then
				t:Stop()
			end

			sounds.WallRun:Stop()
		end)

		local startTime = time()
		stopWallRunConn(plr)
		wallRunConnManager:Set(plr, RunService.Heartbeat:Connect(function(_dt)
			if not char.Parent or humanoid.Health <= 0 then
				destroyVel()
				return
			end

			local elapsed = time() - startTime
			local timePos = math.clamp(1 - (elapsed / Settings.WallRun.wallRunDuration), 0, 1)
			local percentage = lerp(0, 1, timePos)

			if percentage < 0.55 then
				destroyVel()
				return
			end

			if humanoid.FloorMaterial ~= Enum.Material.Air then
				destroyVel()
				return
			end

			local forwardRay =
				workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * Settings.WallRun.wallRunRange, wallRunParams)
			if forwardRay then
				local forwardNormal = forwardRay.Normal
				local dot = math.clamp(wallNormal:Dot(forwardNormal), -1, 1)
				local angleDiff = math.deg(math.acos(dot))
				if angleDiff > 50 then
					destroyVel()
					return
				end

				wallDirection = forwardNormal:Cross(Vector3.new(0, direction, 0))
				updateOrientation(forwardNormal)
			end

			if direction == -1 then
				local leftCheck =
					workspace:Raycast(hrp.Position, hrp.CFrame.RightVector * -Settings.WallRun.wallRunRange, wallRunParams)
				if not leftCheck then
					destroyVel()
					return
				end
			elseif direction == 1 then
				local rightCheck =
					workspace:Raycast(hrp.Position, hrp.CFrame.RightVector * Settings.WallRun.wallRunRange, wallRunParams)
				if not rightCheck then
					destroyVel()
					return
				end
			end

			local currentVel = Settings.WallRun.wallRunSpeed * percentage
			bodyVel.VectorVelocity = wallDirection * currentVel + Vector3.new(0, -Settings.WallRun.wallRunDownwardSpeed, 0)
		end))
	end
end

return ActionsClimbWall
