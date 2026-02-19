local ActionsDash = {}
local DASH_SERVER_ACK_TIMEOUT = 0.3
local DASH_SERVER_ACK_POLL_DT = 0.01

function ActionsDash.Bind(module, context)
	local Settings = context.Settings
	local RunService = context.RunService
	local Main = context.Main
	local Global = context.Global
	local StateManager = context.StateManager
	local canUse = context.canUse
	local isCarryOrGripBlocked = context.isCarryOrGripBlocked
	local AnimsHandler = context.AnimsHandler
	local getDashAnimIdFromDir = context.getDashAnimIdFromDir
	local getDashRenderStepKey = context.getDashRenderStepKey
	local unbindDashRenderStep = context.unbindDashRenderStep
	local sounds = context.sounds
	local Gravity_Force = context.Gravity_Force

	local function isDefenseActive(plr: Player, char: Model): boolean
		if
			char:GetAttribute("isBlocking") == true
			or char:GetAttribute("Parrying") == true
			or char:GetAttribute("AutoParryActive") == true
		then
			return true
		end

		return StateManager.GetState(plr, "isBlocking") == true or StateManager.GetState(plr, "Parrying") == true
	end

	local function waitForDashServerAck(char: Model): boolean
		local deadline = os.clock() + DASH_SERVER_ACK_TIMEOUT
		while os.clock() < deadline do
			if not char.Parent then
				return false
			end
			if char:GetAttribute("Dashing") == true then
				return true
			end
			task.wait(DASH_SERVER_ACK_POLL_DT)
		end

		return char.Parent ~= nil and char:GetAttribute("Dashing") == true
	end

	function module.Dash(plr: Player, direction: Vector3, cancel: boolean)
		if not plr or not direction then
			return
		end
		if isCarryOrGripBlocked(plr) then
			return
		end
		if not canUse(plr, "Dash") then
			return
		end

		local char = plr.Character
		if not char then
			return
		end
		if isDefenseActive(plr, char) then
			return
		end

		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then
			return
		end

		local dashDire = hrp.CFrame:VectorToWorldSpace(direction)
		dashDire = Vector3.new(dashDire.X, 0, dashDire.Z)
		if dashDire.Magnitude <= 0 then
			return
		end
		dashDire = dashDire.Unit

		local dashDuration = Settings.Dash.Duration
		local dashDistance = Settings.Dash.Distance
		if cancel == true then
			dashDuration = Settings.Dash.CancelDur
			dashDistance = Settings.Dash.CancelDist
		end

		local animId = getDashAnimIdFromDir(direction, cancel)

		Main:FireServer("dash", true)
		if not waitForDashServerAck(char) then
			Main:FireServer("dash", false)
			return
		end

		AnimsHandler.StopAnims(char, "ClimbJumpOff")
		AnimsHandler.StopAnims(char, "ClimbUp")
		AnimsHandler.StopAnims(char, "WallHop")
		if animId then
			AnimsHandler.LoadAnim(char, "Dashing", animId, nil, { replaceType = true })
		end

		local dashSfx = sounds:FindFirstChild("Dash")
		if dashSfx and dashSfx:IsA("Sound") then
			dashSfx:Play()
		end
		Global.FOV({ nil, { 0.05, 75 } })

		local elapsed = 0
		local key = getDashRenderStepKey(plr)

		unbindDashRenderStep(plr)
		RunService:BindToRenderStep(key, Enum.RenderPriority.Character.Value, function(dt)
			elapsed += dt
			if elapsed >= dashDuration or not char.Parent or char:GetAttribute("Dashing") ~= true then
				unbindDashRenderStep(plr)
				Main:FireServer("dash", false)
				Global.FOV({ nil, { 0.2, 70 } })
				return
			end

			local horizontalVelocity = dashDire * dashDistance / dashDuration
			hrp.Velocity = Vector3.new(horizontalVelocity.X, Gravity_Force, horizontalVelocity.Z)
		end)
	end
end

return ActionsDash
