local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MainRemote = Remotes:WaitForChild("Main")

local AnimationHandler =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("AnimationHandler"))
local StateManager =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local StateKeys = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateKeys"))
local CombatNet = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatNet"))
local CombatStateRules =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatStateRules"))
local MovementBlockStates =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("MovementBlockStates"))

local Config = require(script:WaitForChild("Config"))
local ToolEquipAnim = require(script:WaitForChild("Anim"))
local WeaponAnim = require(script:WaitForChild("WeaponAnim"))
local WeaponIdle = require(script:WaitForChild("WeaponIdle"))
local ToolEquipObserve = require(script:WaitForChild("Observe"))

local ToolEquipHandler = {}

local LOCAL_PLAYER = Players.LocalPlayer

local anim = ToolEquipAnim.new({
	Config = Config,
	AnimationHandler = AnimationHandler,
})
local weaponAnim = WeaponAnim.new({
	Config = Config,
	AnimationHandler = AnimationHandler,
})
local weaponIdle = WeaponIdle.new({
	Config = Config,
	AnimationHandler = AnimationHandler,
})

local observer = ToolEquipObserve.new()

local RIGHT_ARM_NAME = "Right Arm"
local LEFT_ARM_NAME = "Left Arm"
local RIGHT_GRIP_NAME = "ToolGrip"
local LEFT_GRIP_NAME = "ToolGrip2"
local RIGHT_GRIP_C0_ONE_HAND = CFrame.new(0.012, -0.834, 0)
local RIGHT_GRIP_C1_UNSELECTED_BODY_ATTACH = CFrame.new(0, -0.6, 1.5) * CFrame.Angles(math.rad(90), 0, 0)
local PREDICTED_RIGHT_GRIP_NAME = "__ClientPredictedToolGrip"
local PREDICTED_LEFT_GRIP_NAME = "__ClientPredictedToolGrip2"

local equippedTool: Tool? = nil
local refreshQueued = false
local runningConn: RBXScriptConnection? = nil
local characterAddedConn: RBXScriptConnection? = nil
local stateMonitorConn: RBXScriptConnection? = nil
local transitionConn: RBXScriptConnection? = nil
local transitionKeyframeConn: RBXScriptConnection? = nil
local isTransitioning = false
local stopRunningCallback = nil
local lastOverlayWanted: boolean? = nil
local lastM1RequestAt = 0
local predictedGripConns: { RBXScriptConnection } = {}
local predictedGripCharacter: Model? = nil

local MIN_LOCAL_M1_INTERVAL = 0.06

local function readLocalState(stateName: string): boolean
	return StateManager.GetState(LOCAL_PLAYER, stateName) == true
end

local function disconnect(conn: RBXScriptConnection?)
	if conn then
		conn:Disconnect()
	end
end

local function disconnectAll(list: { RBXScriptConnection })
	for i = #list, 1, -1 do
		local conn = list[i]
		if conn and conn.Connected then
			conn:Disconnect()
		end
		list[i] = nil
	end
end

local function isRunning(): boolean
	return StateManager.GetState(LOCAL_PLAYER, StateKeys.Running) == true
end

local function isAttackTool(tool: Tool?): boolean
	return tool ~= nil and tool:GetAttribute("Type") == "Attack"
end

local function isSelectedAttackTool(tool: Tool?): boolean
	return isAttackTool(tool) and tool:FindFirstChild("EquipedWeapon") ~= nil
end

local function clearNamedMotor(parent: Instance?, motorName: string)
	if not parent then
		return
	end
	local motor = parent:FindFirstChild(motorName)
	if motor and motor:IsA("Motor6D") then
		motor:Destroy()
	end
end

local function getFirstPartByName(tool: Tool, names: { string }): BasePart?
	for _, name in ipairs(names) do
		local part = tool:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function getAnyPart(tool: Tool): BasePart?
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

local function setMotorWithPrePosition(
	parentPart: BasePart,
	weaponPart: BasePart,
	motorName: string,
	c0: CFrame,
	c1: CFrame
): Motor6D
	clearNamedMotor(parentPart, motorName)

	pcall(function()
		weaponPart.CFrame = parentPart.CFrame * c0 * c1:Inverse()
	end)

	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.C0 = c0
	motor.C1 = c1
	motor.Part0 = parentPart
	motor.Part1 = weaponPart
	motor.Parent = parentPart
	return motor
end

local function clearPredictedGrip()
	disconnectAll(predictedGripConns)

	local char = predictedGripCharacter
	predictedGripCharacter = nil
	if not char then
		return
	end

	local rightArm = char:FindFirstChild(RIGHT_ARM_NAME)
	if rightArm then
		clearNamedMotor(rightArm, PREDICTED_RIGHT_GRIP_NAME)
	end

	local leftArm = char:FindFirstChild(LEFT_ARM_NAME)
	if leftArm then
		clearNamedMotor(leftArm, PREDICTED_LEFT_GRIP_NAME)
	end
end

local function predictAttackGrip(tool: Tool)
	if not isAttackTool(tool) then
		return
	end

	local char = LOCAL_PLAYER.Character
	if not char or tool.Parent ~= char then
		return
	end

	clearPredictedGrip()
	predictedGripCharacter = char

	local rightArm = char:FindFirstChild(RIGHT_ARM_NAME)
	if not rightArm or not rightArm:IsA("BasePart") then
		return
	end

	local rightPart = getFirstPartByName(tool, { "BodyAttach", "Handle", "FalseHandle" }) or getAnyPart(tool)
	if not rightPart then
		return
	end

	local replicatedGrip = rightArm:FindFirstChild(RIGHT_GRIP_NAME)
	if replicatedGrip and replicatedGrip:IsA("Motor6D") then
		return
	end

	-- Disable legacy grip immediately on client to avoid one-frame snap before server grip replication.
	clearNamedMotor(rightArm, "RightGrip")

	local hasSelectionFlag = tool:FindFirstChild("EquipedWeapon") ~= nil
	local rightC0 = RIGHT_GRIP_C0_ONE_HAND
	local rightC1 = CFrame.new()
	if rightPart.Name == "BodyAttach" then
		rightC0 = CFrame.new()
		rightC1 = hasSelectionFlag and CFrame.new() or RIGHT_GRIP_C1_UNSELECTED_BODY_ATTACH
	end

	setMotorWithPrePosition(rightArm, rightPart, PREDICTED_RIGHT_GRIP_NAME, rightC0, rightC1)

	local leftArm = char:FindFirstChild(LEFT_ARM_NAME)
	if leftArm and leftArm:IsA("BasePart") then
		local leftPart = getFirstPartByName(tool, { "BodyAttach2" })
		if leftPart then
			setMotorWithPrePosition(leftArm, leftPart, PREDICTED_LEFT_GRIP_NAME, CFrame.new(), CFrame.new())
		else
			clearNamedMotor(leftArm, PREDICTED_LEFT_GRIP_NAME)
		end
	end

	table.insert(
		predictedGripConns,
		rightArm.ChildAdded:Connect(function(child)
			if child:IsA("Motor6D") and child.Name == RIGHT_GRIP_NAME then
				clearPredictedGrip()
			end
		end)
	)

	if leftArm and leftArm:IsA("BasePart") then
		table.insert(
			predictedGripConns,
			leftArm.ChildAdded:Connect(function(child)
				if child:IsA("Motor6D") and child.Name == LEFT_GRIP_NAME then
					clearPredictedGrip()
				end
			end)
		)
	end

	table.insert(
		predictedGripConns,
		tool.AncestryChanged:Connect(function()
			if tool.Parent ~= char then
				clearPredictedGrip()
			end
		end)
	)
end

local function isAnimTypePlaying(char: Model, animType: string): boolean
	local anims = AnimationHandler.GetAnims(char, animType)
	for _, animData in pairs(anims) do
		local track = animData and animData.Track
		if track and track.IsPlaying then
			return true
		end
	end
	return false
end

local function isWeaponIdleBlockedByState(): boolean
	local char = LOCAL_PLAYER.Character
	if not char or not char.Parent then
		return true
	end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		local state = hum:GetState()
		if
			state == Enum.HumanoidStateType.Jumping
			or state == Enum.HumanoidStateType.Freefall
			or state == Enum.HumanoidStateType.FallingDown
			or state == Enum.HumanoidStateType.Landed
		then
			return true
		end
	end

	if isAnimTypePlaying(char, "Landed") then
		return true
	end

	if StateManager.GetState(LOCAL_PLAYER, StateKeys.Running) == true then
		return true
	end

	if StateManager.GetState(LOCAL_PLAYER, StateKeys.Crouching) == true then
		return true
	end
	if isAnimTypePlaying(char, "Crouch") then
		return true
	end

	if char:GetAttribute("Dashing") == true then
		return true
	end
	if isAnimTypePlaying(char, "Dashing") then
		return true
	end

	for _, stateKey in ipairs(MovementBlockStates.BaseAnimator) do
		if StateManager.GetState(LOCAL_PLAYER, stateKey) == true then
			return true
		end
	end

	if char:GetAttribute("Downed") == true then
		return true
	end
	if char:GetAttribute("Gripped") == true then
		return true
	end
	if char:GetAttribute("Gripping") == true then
		return true
	end
	if char:GetAttribute("Carrying") == true then
		return true
	end
	if char:GetAttribute("Carried") == true then
		return true
	end

	return false
end

local function disconnectTransition()
	if transitionConn then
		transitionConn:Disconnect()
		transitionConn = nil
	end
	if transitionKeyframeConn then
		transitionKeyframeConn:Disconnect()
		transitionKeyframeConn = nil
	end
	isTransitioning = false
	local char = LOCAL_PLAYER.Character
	if char then
		char:SetAttribute("Swing", false)
	end
	StateManager.SetState(LOCAL_PLAYER, StateKeys.Swinging, false, 0, true)
end

local function forceStopRunning()
	if stopRunningCallback then
		local ok = pcall(stopRunningCallback)
		if ok then
			return
		end
	end

	StateManager.SetState(LOCAL_PLAYER, StateKeys.Running, false, 0, true)
end

local function setTransitionSwingLock(enabled: boolean)
	local char = LOCAL_PLAYER.Character
	if char then
		char:SetAttribute("Swing", enabled)
	end
	StateManager.SetState(LOCAL_PLAYER, StateKeys.Swinging, enabled, 0, true)
end

local function requestWeaponEquip(tool: Tool)
	if not isAttackTool(tool) then
		return
	end
	if tool:FindFirstChild("EquipedWeapon") then
		return
	end

	local char = LOCAL_PLAYER.Character
	if not char or tool.Parent ~= char then
		return
	end
	if CombatStateRules.IsEquipBlocked(char) then
		return
	end

	MainRemote:FireServer("inventory", {
		action = "equipWeapon",
		itemId = tool:GetAttribute("InventoryId"),
		itemName = tool:GetAttribute("Name") or tool.Name,
	})
end

local function requestCombatM1(tool: Tool)
	if not isSelectedAttackTool(tool) then
		return
	end
	if isTransitioning then
		return
	end

	local now = os.clock()
	if (now - lastM1RequestAt) < MIN_LOCAL_M1_INTERVAL then
		return
	end

	local char = LOCAL_PLAYER.Character
	if not char or tool.Parent ~= char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local wasRunning = isRunning()
	local isAirborne = humanoid and humanoid.FloorMaterial == Enum.Material.Air or false
	if CombatStateRules.IsM1Blocked(char, readLocalState) then
		return
	end

	lastM1RequestAt = now
	forceStopRunning()
	MainRemote:FireServer("combatM1", CombatNet.EncodeM1Payload(wasRunning, isAirborne))
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true

	task.defer(function()
		refreshQueued = false

		local char = LOCAL_PLAYER.Character
		if not char then
			return
		end

		local shouldOverlayIdle = isSelectedAttackTool(equippedTool) and not isTransitioning and not isWeaponIdleBlockedByState()
		if shouldOverlayIdle then
			if not weaponIdle:isPlaying() and equippedTool then
				weaponIdle:play(char, equippedTool.Name)
			end
		else
			if weaponIdle:isPlaying() then
				weaponIdle:stop(char)
			end
		end

		local shouldPlay = equippedTool ~= nil and equippedTool.Parent ~= nil and not isSelectedAttackTool(equippedTool)
		if Config.StopWhileRunning and isRunning() then
			shouldPlay = false
		end

		if not shouldPlay then
			if anim:isPlaying() then
				anim:stop(char)
			end
			return
		end

		if not anim:isPlaying() then
			anim:play(char)
		end
	end)
end

local function bindRunningSignal()
	disconnect(runningConn)
	runningConn = nil

	local char = LOCAL_PLAYER.Character
	if not char then
		return
	end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	runningConn = hum.Running:Connect(function()
		queueRefresh()
	end)
end

local function bindStateMonitor()
	disconnect(stateMonitorConn)
	stateMonitorConn = nil
	lastOverlayWanted = nil

	stateMonitorConn = RunService.Heartbeat:Connect(function()
		local overlayWanted = isSelectedAttackTool(equippedTool)
			and not isTransitioning
			and not isWeaponIdleBlockedByState()

		if overlayWanted ~= lastOverlayWanted then
			lastOverlayWanted = overlayWanted
			queueRefresh()
			return
		end

		-- Keep idle overlay alive when an animation track stops unexpectedly (e.g. non-looping assets).
		if overlayWanted and not weaponIdle:isPlaying() then
			queueRefresh()
		end
	end)
end

local function shutdown()
	disconnect(characterAddedConn)
	characterAddedConn = nil

	disconnect(runningConn)
	runningConn = nil
	disconnect(stateMonitorConn)
	stateMonitorConn = nil

	observer:Stop()
	disconnectTransition()
	clearPredictedGrip()

	equippedTool = nil
	refreshQueued = false
	stopRunningCallback = nil
	lastOverlayWanted = nil
	lastM1RequestAt = 0

	local char = LOCAL_PLAYER.Character
	if char then
		anim:stop(char)
		weaponAnim:stop(char)
		weaponIdle:stop(char)
	else
		anim:stop(nil)
	end
end

function ToolEquipHandler.Init(options)
	shutdown()
	ToolEquipHandler._initialized = true
	stopRunningCallback = options and options.stopRunning

	observer:Start({
		onEquipped = function(tool)
			equippedTool = tool

			local char = LOCAL_PLAYER.Character
			if char then
				anim:stop(char)
				if isAttackTool(tool) then
					predictAttackGrip(tool)
				end
				if isSelectedAttackTool(tool) then
					forceStopRunning()
					disconnectTransition()
					weaponIdle:stop(char)
					setTransitionSwingLock(true)
					isTransitioning = true

					local track = weaponAnim:playEquip(char, tool.Name)
					if track then
						transitionConn = track.Stopped:Connect(function()
							disconnectTransition()
							queueRefresh()
						end)
						transitionKeyframeConn = track.KeyframeReached:Connect(function(keyframeName)
							if keyframeName == "Equipped" then
								disconnectTransition()
								queueRefresh()
							end
						end)
					else
						disconnectTransition()
					end
				else
					weaponAnim:stop(char)
				end
			end

			queueRefresh()
		end,
		onUnequipped = function(tool)
			if isAttackTool(tool) then
				clearPredictedGrip()
			end

			local char = LOCAL_PLAYER.Character
			if char and isSelectedAttackTool(tool) then
				anim:stop(char)
				forceStopRunning()
				disconnectTransition()
				weaponIdle:stop(char)
				setTransitionSwingLock(true)
				isTransitioning = true

				local track = weaponAnim:playUnequip(char, tool.Name)
				if track then
					transitionConn = track.Stopped:Connect(function()
						disconnectTransition()
						queueRefresh()
					end)
				else
					disconnectTransition()
				end
			end

			if equippedTool == tool then
				equippedTool = nil
			end
			queueRefresh()
		end,
		onActivated = function(tool)
			if isSelectedAttackTool(tool) then
				requestCombatM1(tool)
				return
			end

			requestWeaponEquip(tool)
		end,
		onToolChanged = function(tool)
			if equippedTool == tool then
				queueRefresh()
			end
		end,
		onCharacter = function()
			clearPredictedGrip()
			bindRunningSignal()
			bindStateMonitor()
			queueRefresh()
		end,
	})

	characterAddedConn = LOCAL_PLAYER.CharacterAdded:Connect(function()
		clearPredictedGrip()
		bindRunningSignal()
		bindStateMonitor()
		queueRefresh()
	end)

	if LOCAL_PLAYER.Character then
		bindRunningSignal()
		bindStateMonitor()
	end

	queueRefresh()
end

function ToolEquipHandler.Shutdown()
	shutdown()
	ToolEquipHandler._initialized = false
end

return ToolEquipHandler
