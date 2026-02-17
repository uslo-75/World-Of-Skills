local ActionsRunning = {}

function ActionsRunning.Bind(module, context)
	local StateManager = context.StateManager
	local Settings = context.Settings
	local RunService = context.RunService
	local Global = context.Global
	local camera = context.camera
	local runConnManager = context.runConnManager
	local landingLock = context.landingLock
	local isGripBlocked = context.isGripBlocked
	local setMomentumVfx = context.setMomentumVfx

	function module.Running(action: string, plr: Player, _toolname: string?)
		local char = plr.Character
		if not char then
			return
		end

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if action == "Play" then
			if isGripBlocked(plr) then
				return
			end
			if landingLock[char] then
				return
			end

			runConnManager:Set("main", RunService.Heartbeat:Connect(function(_dt)
				if not char.Parent or humanoid.Health <= 0 then
					setMomentumVfx(char, false)
					runConnManager:Disconnect("main")
					return
				end

				local isRunning = StateManager.GetState(plr, "Running") == true
				if camera.FieldOfView < Settings.Camera.MaxFOV and isRunning then
					local target = math.min(camera.FieldOfView + 0.2, Settings.Camera.MaxFOV)
					Global.FOV({ nil, { 0.1, target } })
				end

				if
					humanoid.WalkSpeed < Settings.Run.Max
					and isRunning
					and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
				then
					humanoid.WalkSpeed += 0.02
				end

				if humanoid.WalkSpeed >= Settings.Run.Max then
					setMomentumVfx(char, true)
				end
			end))

			StateManager.SetState(plr, "Running", true, 0, true)
			humanoid.WalkSpeed = Settings.Run.Extra
		else
			runConnManager:Disconnect("main")

			humanoid.WalkSpeed = Settings.Run.Normal
			StateManager.SetState(plr, "Running", false, 0, true)
			Global.FOV({ nil, { 0.4, 70 } })
			setMomentumVfx(char, false)
		end
	end
end

return ActionsRunning
