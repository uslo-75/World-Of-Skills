local RS = game:GetService("ReplicatedStorage")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ModulesFolder = script:WaitForChild("Modules")
local CharacterModulesFolder = script.Parent.Parent:WaitForChild("CharacterModules")

local actions = require(ModulesFolder:WaitForChild("Actions"))
local Settings = require(ModulesFolder:WaitForChild("Settings"))
local StateManager = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local StateKeys = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateKeys"))
local ToolEquipHandler = require(RS:WaitForChild("LocalHandler"):WaitForChild("Misc"):WaitForChild("ToolEquipHadler"))

local DirectionalWalk = require(CharacterModulesFolder:WaitForChild("DirectionalWalk"))
local EventsBridge = require(CharacterModulesFolder:WaitForChild("EventsBridge"))
local FootstepMaterials = require(CharacterModulesFolder:WaitForChild("FootstepMaterials"))
local RagdollClient = require(CharacterModulesFolder:WaitForChild("RagdollClient"))
local PlatformStabilizer = require(CharacterModulesFolder:WaitForChild("PlatformStabilizer"))
local DeathShutdown = require(CharacterModulesFolder:WaitForChild("DeathShutdown"))

local Plr = Players.LocalPlayer
local char: Model = Plr.Character or Plr.CharacterAdded:Wait()
local hum: Humanoid = char:WaitForChild("Humanoid")
local hrp: BasePart = char:WaitForChild("HumanoidRootPart")

ToolEquipHandler.Init()
DirectionalWalk.Init()
EventsBridge.Init()
FootstepMaterials.Init()
RagdollClient.Init()
PlatformStabilizer.Init()
DeathShutdown.Init({
	controllerScript = script,
})

local ActiveKeys = { W = false, A = false, S = false, D = false }
local lastPressed: string? = nil

local lastWpressTime = 0
local IsCancel
local Sprint_Threshold = 0.2

local canVaultTick = 0
local VAULT_CHECK_DT = 0.10

local downConn: RBXScriptConnection? = nil
local ragdollConn: RBXScriptConnection? = nil
local grippingConn: RBXScriptConnection? = nil
local function setHumanoidStatesDisabled(h: Humanoid)
	for _, state in ipairs({
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.FallingDown,
	}) do
		h:SetStateEnabled(state, false)
	end
end

local function syncDownRagdollStates()
	if not char or not char.Parent then
		return
	end

	local isDown = char:GetAttribute("Downed") == true
	local isRagdoll = char:GetAttribute("IsRagdoll") == true
	local isGripping = char:GetAttribute("Gripping") == true

	StateManager.SetState(Plr, StateKeys.Downed, isDown)
	StateManager.SetState(Plr, StateKeys.IsRagdoll, isRagdoll)
	StateManager.SetState(Plr, StateKeys.Gripping, isGripping)

	if isDown or isRagdoll or isGripping then
		actions.Running("Stop", Plr, "None")
		if StateManager.GetState(Plr, StateKeys.Sliding) == true then
			actions.SlideStop(Plr)
		end
		if StateManager.GetState(Plr, StateKeys.Crouching) == true then
			actions.CrouchToggle("Stop", Plr)
		end
	end
end

local function bindDownRagdollSignals(character: Model)
	if downConn then
		downConn:Disconnect()
		downConn = nil
	end
	if ragdollConn then
		ragdollConn:Disconnect()
		ragdollConn = nil
	end
	if grippingConn then
		grippingConn:Disconnect()
		grippingConn = nil
	end

	downConn = character:GetAttributeChangedSignal("Downed"):Connect(syncDownRagdollStates)
	ragdollConn = character:GetAttributeChangedSignal("IsRagdoll"):Connect(syncDownRagdollStates)
	grippingConn = character:GetAttributeChangedSignal("Gripping"):Connect(syncDownRagdollStates)
	syncDownRagdollStates()
end

local function onCharacterAdded(newchar: Model)
	char = newchar
	hum = newchar:WaitForChild("Humanoid")
	hrp = newchar:WaitForChild("HumanoidRootPart")

	StateManager.SetState(Plr, StateKeys.Running, false, 0, true)

	actions.OnCharacterAdded(Plr)

	setHumanoidStatesDisabled(hum)
	bindDownRagdollSignals(newchar)
end

local function onCharacterRemoving(_oldChar: Model)
	actions.OnCharacterRemoving(Plr, _oldChar)
end

Plr.CharacterAdded:Connect(onCharacterAdded)
Plr.CharacterRemoving:Connect(onCharacterRemoving)
actions.OnCharacterAdded(Plr)
setHumanoidStatesDisabled(hum)
bindDownRagdollSignals(char)

local function isMovementLocked(): boolean
	return StateManager.GetState(Plr, StateKeys.Downed) == true
		or StateManager.GetState(Plr, StateKeys.IsRagdoll) == true
		or (char and char:GetAttribute("Gripping") == true)
end

local function hasValidMoveDirection(): boolean
	local vertical = 0
	local horizontal = 0

	if ActiveKeys.W then
		vertical += 1
	end
	if ActiveKeys.S then
		vertical -= 1
	end
	if ActiveKeys.A then
		horizontal -= 1
	end
	if ActiveKeys.D then
		horizontal += 1
	end

	return not (vertical == 0 and horizontal == 0)
end

local function getDashDirection(): Vector3?
	local vertical = 0
	local horizontal = 0

	if ActiveKeys.W then
		vertical += 1
	end
	if ActiveKeys.S then
		vertical -= 1
	end
	if ActiveKeys.A then
		horizontal -= 1
	end
	if ActiveKeys.D then
		horizontal += 1
	end

	if vertical == 0 and horizontal == 0 then
		if lastPressed == "W" then
			vertical = 1
		elseif lastPressed == "S" then
			vertical = -1
		elseif lastPressed == "D" then
			horizontal = 1
		elseif lastPressed == "A" then
			horizontal = -1
		end
	end

	local dir = Vector3.new(horizontal, 0, -vertical)
	return (dir.Magnitude > 0) and dir.Unit or nil
end

local function stepped(dt: number)
	if not char or not char.Parent then
		return
	end
	if not hum or not hrp then
		return
	end
	local locked = isMovementLocked()
	if not locked then
		actions.UpdateClimbLock(Plr, hum)

		canVaultTick += dt
		if canVaultTick >= VAULT_CHECK_DT then
			canVaultTick = 0
			actions.VaultCheck(Plr)
		end
	end

	actions.UpdateFall(Plr, char, hum, hrp, dt)
end

RunService.RenderStepped:Connect(function(dt)
	xpcall(stepped, function(err)
		warn(
			"\n---------------------------\nCharacterClient RenderStepped loop error\nError:\n"
				.. tostring(err)
				.. "\n\nTrace:\n"
				.. debug.traceback()
				.. "\n---------------------------"
		)
	end, dt)
end)

local function onInput(actionName: string, inputState: Enum.UserInputState, _inputObject)
	if actionName == "Mouse2" then
		if inputState == Enum.UserInputState.Begin then
			Settings.Combats.lastMouseButton2Pressed = tick()
		end
		return Enum.ContextActionResult.Pass
	end

	if inputState == Enum.UserInputState.Begin then
		if isMovementLocked() then
			return
		end
		if actionName == "Dash" then
			if
				StateManager.GetState(Plr, StateKeys.Crouching)
				or StateManager.GetState(Plr, StateKeys.Swinging)
				or StateManager.GetState(Plr, StateKeys.Sliding)
				or StateManager.GetState(Plr, StateKeys.Dashing)
				or StateManager.GetState(Plr, StateKeys.Climbing)
				or StateManager.GetState(Plr, StateKeys.Vaulting)
				or StateManager.GetState(Plr, StateKeys.Stunned)
				or StateManager.GetState(Plr, StateKeys.WallRunning)
				or StateManager.GetState(Plr, StateKeys.WallHopping)
				or StateManager.GetState(Plr, StateKeys.ClimbUp)
				or StateManager.GetState(Plr, StateKeys.SlidePush)
			then
				return
			end

			local dir = getDashDirection()
			if dir then
				if Settings.Combats.lastMouseButton2Pressed then
					IsCancel = tick() - Settings.Combats.lastMouseButton2Pressed or 1
					if IsCancel <= 0.25 then
						actions.Dash(Plr, dir, true)
					else
						actions.Dash(Plr, dir, nil)
					end
				else
					actions.Dash(Plr, dir, nil)
				end
			end
			return
		end

		if actionName == "W" or actionName == "A" or actionName == "S" or actionName == "D" then
			ActiveKeys[actionName] = true
			lastPressed = actionName

			-- crouch: block sprint/run logic
			if StateManager.GetState(Plr, StateKeys.Crouching) then
				return
			end

			if not hasValidMoveDirection() then
				actions.Running("Stop", Plr, "None")
				return
			end

			if actionName == "W" then
				local now = tick()
				if now - lastWpressTime <= Sprint_Threshold then
					actions.Running("Play", Plr, "None")
				else
					lastWpressTime = now
				end
			end
			return
		end

		if actionName == "SpaceInput" then
			if StateManager.GetState(Plr, StateKeys.Crouching) then
				return
			end

			if
				StateManager.GetState(Plr, StateKeys.Swinging)
				or StateManager.GetState(Plr, StateKeys.Dashing)
				or StateManager.GetState(Plr, StateKeys.Stunned)
				or StateManager.GetState(Plr, StateKeys.SlowStunned)
				or StateManager.GetState(Plr, StateKeys.IsRagdoll)
				or StateManager.GetState(Plr, StateKeys.Blocking)
				or StateManager.GetState(Plr, StateKeys.Parrying)
				or StateManager.GetState(Plr, StateKeys.UsingMove)
			then
				return
			end

			if StateManager.GetState(Plr, StateKeys.Sliding) == true then
				actions.SlidePush(Plr)
				return
			end

			local wallRunVel = hrp:FindFirstChild("WallRunVelocity")
			if wallRunVel then
				local dirValue = wallRunVel:FindFirstChild("Direction")
				local dir = dirValue and dirValue.Value
				wallRunVel:Destroy()
				if dir ~= nil then
					actions.WallRunJumpOff(Plr, dir)
				end
			end

			local primary = char.PrimaryPart or hrp
			if
				primary
				and primary:FindFirstChild("ClimbingAlign")
				and hrp:FindFirstChild("ClimbingVelocity")
				and not StateManager.GetState(Plr, StateKeys.ClimbUp)
			then
				StateManager.SetState(Plr, StateKeys.ClimbDisengage, true, 0, true)
				task.delay(0.4, function()
					StateManager.SetState(Plr, StateKeys.ClimbDisengage, false, 0, true)
				end)
			end

			if not StateManager.GetState(Plr, StateKeys.Climbing) and hum.FloorMaterial == Enum.Material.Air then
				if
					StateManager.GetState(Plr, StateKeys.Crouching)
					or StateManager.GetState(Plr, StateKeys.Swinging)
					or StateManager.GetState(Plr, StateKeys.Sliding)
					or StateManager.GetState(Plr, StateKeys.Dashing)
					or StateManager.GetState(Plr, StateKeys.Climbing)
					or StateManager.GetState(Plr, StateKeys.Vaulting)
					or StateManager.GetState(Plr, StateKeys.Stunned)
					or StateManager.GetState(Plr, StateKeys.WallRunning)
					or StateManager.GetState(Plr, StateKeys.WallHopping)
					or StateManager.GetState(Plr, StateKeys.ClimbUp)
				then
					return
				end

				task.spawn(function()
					actions.MovementClimb(Plr)
				end)
			end

			return
		end

		if actionName == "CtrlInput" then
			if
				StateManager.GetState(Plr, StateKeys.Swinging)
				or StateManager.GetState(Plr, StateKeys.Dashing)
				or StateManager.GetState(Plr, StateKeys.Stunned)
				or StateManager.GetState(Plr, StateKeys.SlowStunned)
				or StateManager.GetState(Plr, StateKeys.IsRagdoll)
				or StateManager.GetState(Plr, StateKeys.Blocking)
				or StateManager.GetState(Plr, StateKeys.Parrying)
				or StateManager.GetState(Plr, StateKeys.UsingMove)
			then
				return
			end

			if not StateManager.GetState(Plr, StateKeys.Sliding) and hum.FloorMaterial ~= Enum.Material.Air then
				if
					StateManager.GetState(Plr, StateKeys.Running)
					and not StateManager.GetState(Plr, StateKeys.Crouching)
				then
					actions.SlideStart(Plr)
				else
					if StateManager.GetState(Plr, StateKeys.Crouching) then
						actions.CrouchToggle("Stop", Plr)
					else
						actions.CrouchToggle("Play", Plr)
					end
				end
			end

			if not StateManager.GetState(Plr, StateKeys.WallRunning) and hum.FloorMaterial == Enum.Material.Air then
				if StateManager.GetState(Plr, StateKeys.Crouching) then
					return
				end

				local wallRunParams = RaycastParams.new()
				wallRunParams.FilterDescendantsInstances = { char }
				wallRunParams.FilterType = Enum.RaycastFilterType.Exclude

				local leftRay = workspace:Raycast(
					hrp.Position,
					hrp.CFrame.RightVector * -Settings.WallRun.wallRunRange,
					wallRunParams
				)
				local rightRay = workspace:Raycast(
					hrp.Position,
					hrp.CFrame.RightVector * Settings.WallRun.wallRunRange,
					wallRunParams
				)

				if leftRay or rightRay then
					local function chooseWallRay()
						if leftRay and rightRay then
							return (leftRay.Position - hrp.Position).Magnitude
										< (rightRay.Position - hrp.Position).Magnitude
									and leftRay
								or rightRay
						end
						return leftRay or rightRay
					end
					local chosenRay = chooseWallRay()
					if chosenRay then
						actions.WallRun(Plr, chosenRay, chosenRay == leftRay and -1 or 1, wallRunParams)
					end
				end
			end

			return
		end
	elseif inputState == Enum.UserInputState.End then
		if actionName == "W" or actionName == "A" or actionName == "S" or actionName == "D" then
			ActiveKeys[actionName] = false
			if not StateManager.GetState(Plr, StateKeys.Crouching) and not hasValidMoveDirection() then
				actions.Running("Stop", Plr, "None")
			end
		end
	end
end

local function bindInputs()
	CAS:BindActionAtPriority(
		"Mouse2",
		onInput,
		false,
		Enum.ContextActionPriority.Low.Value,
		Enum.UserInputType.MouseButton2
	)
	CAS:BindAction("Dash", onInput, false, Enum.KeyCode.Q)
	CAS:BindActionAtPriority("W", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.W)
	CAS:BindActionAtPriority("A", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.A)
	CAS:BindActionAtPriority("S", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.S)
	CAS:BindActionAtPriority("D", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.D)
	CAS:BindAction("CtrlInput", onInput, false, Enum.KeyCode.LeftControl)
	CAS:BindActionAtPriority("SpaceInput", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.Space)
end

bindInputs()
