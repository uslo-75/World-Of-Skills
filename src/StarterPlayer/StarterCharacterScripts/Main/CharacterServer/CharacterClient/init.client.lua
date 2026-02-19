local RS = game:GetService("ReplicatedStorage")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local ModulesFolder = script:WaitForChild("Modules")
local CharacterModulesFolder = script.Parent.Parent:WaitForChild("CharacterModules")

local actions = require(ModulesFolder:WaitForChild("Actions"))
local Settings = require(ModulesFolder:WaitForChild("Settings"))
local StateManager = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local StateKeys = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateKeys"))
local CombatNet = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatNet"))
local CombatStateRules = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatStateRules"))
local AnimationHandler = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("AnimationHandler"))
local ToolEquipHandler = require(RS:WaitForChild("LocalHandler"):WaitForChild("Misc"):WaitForChild("ToolEquipHadler"))
local MainRemote = RS:WaitForChild("Remotes"):WaitForChild("Main")

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

ToolEquipHandler.Init({
	stopRunning = function()
		actions.Running("Stop", Plr, "None")
	end,
})
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

local BLOCK_WALK_SPEED = math.max(0, tonumber(Settings.Combats.blockWalkSpeed) or 6)
local BLOCK_ANIM_TYPE = "WeaponBlockOverlay"
local BLOCK_TRACK_NAME = "WeaponBlockOverlayTrack"
local BLOCK_ANIM_FADE = 0.08
local BLOCK_ANIM_PRIORITY = Enum.AnimationPriority.Action2

local downConn: RBXScriptConnection? = nil
local ragdollConn: RBXScriptConnection? = nil
local grippingConn: RBXScriptConnection? = nil
local stunnedConn: RBXScriptConnection? = nil
local slowStunnedConn: RBXScriptConnection? = nil
local swingConn: RBXScriptConnection? = nil
local attackingConn: RBXScriptConnection? = nil
local blockingConn: RBXScriptConnection? = nil
local parryingConn: RBXScriptConnection? = nil
local blockInputActive = false
local blockTrack: AnimationTrack? = nil
local blockTrackStoppedConn: RBXScriptConnection? = nil
local defenseStopSyncSent = false
local lastCriticalRequestAt = 0
local MIN_LOCAL_CRITICAL_INTERVAL = 0.1
local MIN_LOCAL_SKILL_INTERVAL = 0.1
local SKILL_KEY_BY_ACTION = {
	SkillInputZ = "Z",
	SkillInputX = "X",
	SkillInputC = "C",
}
local lastSkillRequestAt = {
	Z = 0,
	X = 0,
	C = 0,
}
local BLOCK_START_PAYLOAD = CombatNet.EncodeBlockAction("Start") or "S"
local BLOCK_STOP_PAYLOAD = CombatNet.EncodeBlockAction("Stop") or "E"
local CRITICAL_USE_PAYLOAD = CombatNet.EncodeCriticalAction("Use") or "U"

local function sendBlockAction(actionPayload: string)
	MainRemote:FireServer("combatBlock", actionPayload)
end

local function sendCriticalUse()
	MainRemote:FireServer("combatCritical", CRITICAL_USE_PAYLOAD)
end

local function sendSkillUse(skillKey: string, tool: Tool?)
	local payload = CombatNet.EncodeSkillPayload(skillKey, tool and tool.Name or nil)
	if not payload then
		return
	end

	MainRemote:FireServer("combatSkill", payload)
end

local function setHumanoidStatesDisabled(h: Humanoid)
	for _, state in ipairs({
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.FallingDown,
	}) do
		h:SetStateEnabled(state, false)
	end
end

local function disconnectCombatSignals()
	if swingConn then
		swingConn:Disconnect()
		swingConn = nil
	end
	if attackingConn then
		attackingConn:Disconnect()
		attackingConn = nil
	end
end

local function isCombatActionLocked(character: Model?): boolean
	if not character then
		return false
	end
	return character:GetAttribute("Swing") == true or character:GetAttribute("Attacking") == true
end

local function syncCombatActionStates()
	if not char or not char.Parent then
		return
	end

	local locked = isCombatActionLocked(char)
	StateManager.SetState(Plr, StateKeys.Swinging, locked, 0, true)

	if locked then
		actions.Running("Stop", Plr, "None")
		AnimationHandler.StopAnims(char, "WeaponIdleOverlay")
		if StateManager.GetState(Plr, StateKeys.Sliding) == true then
			actions.SlideStop(Plr)
		end
		if StateManager.GetState(Plr, StateKeys.Crouching) == true then
			actions.CrouchToggle("Stop", Plr)
		end
		return
	end

	if hum then
		local shouldRun = StateManager.GetState(Plr, StateKeys.Running) == true
		hum.WalkSpeed = shouldRun and Settings.Run.Extra or Settings.Run.Normal
	end
end

local function bindCombatSignals(character: Model)
	disconnectCombatSignals()
	swingConn = character:GetAttributeChangedSignal("Swing"):Connect(syncCombatActionStates)
	attackingConn = character:GetAttributeChangedSignal("Attacking"):Connect(syncCombatActionStates)
	syncCombatActionStates()
end

local function disconnectDefenseSignals()
	if blockingConn then
		blockingConn:Disconnect()
		blockingConn = nil
	end
	if parryingConn then
		parryingConn:Disconnect()
		parryingConn = nil
	end
end

local function getSelectedAttackTool(character: Model?): Tool?
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if
			child:IsA("Tool")
			and child:GetAttribute("Type") == "Attack"
			and child:FindFirstChild("EquipedWeapon") ~= nil
		then
			return child
		end
	end

	return nil
end

local function hasSelectedAttackTool(character: Model?): boolean
	return getSelectedAttackTool(character) ~= nil
end

local function findAnimationIn(parent: Instance?, names: { string }): Animation?
	if not parent then
		return nil
	end

	for _, name in ipairs(names) do
		local anim = parent:FindFirstChild(name)
		if anim and anim:IsA("Animation") then
			return anim
		end
	end

	return nil
end

local function resolveBlockAnimation(character: Model): Animation?
	local tool = getSelectedAttackTool(character)
	if not tool then
		return nil
	end

	local assets = RS:FindFirstChild("Assets")
	local animationRoot = assets and assets:FindFirstChild("animation")
	local combatRoot = animationRoot and animationRoot:FindFirstChild("combat")
	if not combatRoot then
		return nil
	end

	local folderNames = { tool.Name }
	local displayName = tool:GetAttribute("Name")
	if typeof(displayName) == "string" and displayName ~= "" and displayName ~= tool.Name then
		table.insert(folderNames, displayName)
	end
	local aliasName = tool:GetAttribute("Weapon")
	if typeof(aliasName) == "string" and aliasName ~= "" then
		local duplicate = false
		for _, name in ipairs(folderNames) do
			if name == aliasName then
				duplicate = true
				break
			end
		end
		if not duplicate then
			table.insert(folderNames, aliasName)
		end
	end

	local weaponFolder: Folder? = nil
	for _, folderName in ipairs(folderNames) do
		local found = combatRoot:FindFirstChild(folderName)
		if found and found:IsA("Folder") then
			weaponFolder = found
			break
		end
	end
	if not weaponFolder then
		return nil
	end

	local direct = findAnimationIn(weaponFolder, { "block", "Block", "blocking", "Blocking" })
	if direct then
		return direct
	end

	for _, containerName in ipairs({ "Blocking", "blocking", "Block", "block" }) do
		local node = weaponFolder:FindFirstChild(containerName)
		if node and node:IsA("Animation") then
			return node
		end
		if node and node:IsA("Folder") then
			local nested =
				findAnimationIn(node, { "idle", "Idle", "hold", "Hold", "block", "Block", "blocking", "Blocking" })
			if nested then
				return nested
			end
			for _, child in ipairs(node:GetChildren()) do
				if child:IsA("Animation") then
					return child
				end
			end
		end
	end

	return nil
end

local function playBlockAnimation()
	if not char or not char.Parent then
		return
	end
	if blockTrack and blockTrack.IsPlaying then
		return
	end

	AnimationHandler.StopAnims(char, "WeaponIdleOverlay")

	local anim = resolveBlockAnimation(char)
	if not anim then
		return
	end

	local track = AnimationHandler.LoadAnim(char, BLOCK_ANIM_TYPE, anim.AnimationId, nil, {
		replaceType = true,
		priority = BLOCK_ANIM_PRIORITY,
		fadeTime = BLOCK_ANIM_FADE,
		looped = true,
	})
	if track then
		track.Name = BLOCK_TRACK_NAME
		if blockTrackStoppedConn then
			blockTrackStoppedConn:Disconnect()
			blockTrackStoppedConn = nil
		end
		blockTrack = track
		blockTrackStoppedConn = track.Stopped:Connect(function()
			if blockTrack == track then
				blockTrack = nil
			end
		end)
	end
end

local function stopBlockAnimation()
	if blockTrackStoppedConn then
		blockTrackStoppedConn:Disconnect()
		blockTrackStoppedConn = nil
	end
	if blockTrack then
		pcall(function()
			blockTrack:Stop(BLOCK_ANIM_FADE)
		end)
		blockTrack = nil
	end
	if not char then
		return
	end
	AnimationHandler.StopAnims(char, BLOCK_ANIM_TYPE)
end

local function canRestoreWalkAfterBlock(): boolean
	if not char or not hum or not hum.Parent then
		return false
	end

	return char:GetAttribute("Stunned") ~= true
		and char:GetAttribute("SlowStunned") ~= true
		and char:GetAttribute("IsRagdoll") ~= true
		and char:GetAttribute("Downed") ~= true
		and char:GetAttribute("Swing") ~= true
		and char:GetAttribute("Attacking") ~= true
end

local function syncDefenseStates()
	if not char or not char.Parent then
		return
	end

	local isBlocking = char:GetAttribute("isBlocking") == true
	local isParrying = char:GetAttribute("Parrying") == true
	StateManager.SetState(Plr, StateKeys.Blocking, isBlocking)
	StateManager.SetState(Plr, StateKeys.Parrying, isParrying)

	if isBlocking or isParrying then
		actions.Running("Stop", Plr, "None")
		if StateManager.GetState(Plr, StateKeys.Sliding) == true then
			actions.SlideStop(Plr)
		end
		if StateManager.GetState(Plr, StateKeys.Crouching) == true then
			actions.CrouchToggle("Stop", Plr)
		end
		AnimationHandler.StopAnims(char, "WeaponIdleOverlay")
	end

	if hum and hum.Parent then
		if isBlocking then
			hum.WalkSpeed = BLOCK_WALK_SPEED
			playBlockAnimation()
		elseif isParrying then
			playBlockAnimation()
			if canRestoreWalkAfterBlock() then
				local shouldRun = StateManager.GetState(Plr, StateKeys.Running) == true
				hum.WalkSpeed = shouldRun and Settings.Run.Extra or Settings.Run.Normal
			end
		else
			stopBlockAnimation()
			if canRestoreWalkAfterBlock() then
				local shouldRun = StateManager.GetState(Plr, StateKeys.Running) == true
				hum.WalkSpeed = shouldRun and Settings.Run.Extra or Settings.Run.Normal
			end
		end
	end
end

local function bindDefenseSignals(character: Model)
	disconnectDefenseSignals()
	blockingConn = character:GetAttributeChangedSignal("isBlocking"):Connect(syncDefenseStates)
	parryingConn = character:GetAttributeChangedSignal("Parrying"):Connect(syncDefenseStates)
	syncDefenseStates()
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

local function disconnectStunSignals()
	if stunnedConn then
		stunnedConn:Disconnect()
		stunnedConn = nil
	end
	if slowStunnedConn then
		slowStunnedConn:Disconnect()
		slowStunnedConn = nil
	end
end

local function syncStunStates()
	if not char or not char.Parent then
		return
	end

	local isStunned = char:GetAttribute("Stunned") == true
	local isSlowStunned = char:GetAttribute("SlowStunned") == true

	StateManager.SetState(Plr, StateKeys.Stunned, isStunned)
	StateManager.SetState(Plr, StateKeys.SlowStunned, isSlowStunned)

	if isStunned or isSlowStunned then
		actions.Running("Stop", Plr, "None")
		if StateManager.GetState(Plr, StateKeys.Sliding) == true then
			actions.SlideStop(Plr)
		end
		if StateManager.GetState(Plr, StateKeys.Crouching) == true then
			actions.CrouchToggle("Stop", Plr)
		end
	end
end

local function bindStunSignals(character: Model)
	disconnectStunSignals()
	stunnedConn = character:GetAttributeChangedSignal("Stunned"):Connect(syncStunStates)
	slowStunnedConn = character:GetAttributeChangedSignal("SlowStunned"):Connect(syncStunStates)
	syncStunStates()
end

local function onCharacterAdded(newchar: Model)
	char = newchar
	hum = newchar:WaitForChild("Humanoid")
	hrp = newchar:WaitForChild("HumanoidRootPart")
	blockInputActive = false
	defenseStopSyncSent = false
	lastCriticalRequestAt = 0
	lastSkillRequestAt.Z = 0
	lastSkillRequestAt.X = 0
	lastSkillRequestAt.C = 0
	stopBlockAnimation()

	StateManager.SetState(Plr, StateKeys.Running, false, 0, true)

	actions.OnCharacterAdded(Plr)

	setHumanoidStatesDisabled(hum)
	bindDownRagdollSignals(newchar)
	bindStunSignals(newchar)
	bindCombatSignals(newchar)
	bindDefenseSignals(newchar)
end

local function onCharacterRemoving(_oldChar: Model)
	if blockInputActive then
		blockInputActive = false
		defenseStopSyncSent = true
		sendBlockAction(BLOCK_STOP_PAYLOAD)
	end
	stopBlockAnimation()
	disconnectCombatSignals()
	disconnectDefenseSignals()
	disconnectStunSignals()
	StateManager.SetState(Plr, StateKeys.Swinging, false, 0, true)
	StateManager.SetState(Plr, StateKeys.Blocking, false)
	StateManager.SetState(Plr, StateKeys.Parrying, false)
	StateManager.SetState(Plr, StateKeys.Stunned, false)
	StateManager.SetState(Plr, StateKeys.SlowStunned, false)
	actions.OnCharacterRemoving(Plr, _oldChar)
end

Plr.CharacterAdded:Connect(onCharacterAdded)
Plr.CharacterRemoving:Connect(onCharacterRemoving)
actions.OnCharacterAdded(Plr)
setHumanoidStatesDisabled(hum)
bindDownRagdollSignals(char)
bindStunSignals(char)
bindCombatSignals(char)
bindDefenseSignals(char)

local function isMovementLocked(): boolean
	return StateManager.GetState(Plr, StateKeys.Downed) == true
		or StateManager.GetState(Plr, StateKeys.IsRagdoll) == true
		or (char and char:GetAttribute("Gripping") == true)
end

local function isDefenseActive(): boolean
	if not char or not char.Parent then
		return false
	end

	if CombatStateRules.IsDefenseActive(char) then
		return true
	end

	return StateManager.GetState(Plr, StateKeys.Blocking) == true or StateManager.GetState(Plr, StateKeys.Parrying) == true
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

	local isBlockKeyDown = UIS:IsKeyDown(Enum.KeyCode.F)

	if blockInputActive and not isBlockKeyDown then
		blockInputActive = false
		sendBlockAction(BLOCK_STOP_PAYLOAD)
		defenseStopSyncSent = true
	end

	local serverDefenseActive = CombatStateRules.IsDefenseActive(char)
	if serverDefenseActive and not isBlockKeyDown then
		if not defenseStopSyncSent then
			defenseStopSyncSent = true
			blockInputActive = false
			sendBlockAction(BLOCK_STOP_PAYLOAD)
		end
	else
		defenseStopSyncSent = false
	end

	local locked = isMovementLocked()
	local defenseActive = isDefenseActive()
	if not locked and not defenseActive then
		actions.UpdateClimbLock(Plr, hum)

		canVaultTick += dt
		if canVaultTick >= VAULT_CHECK_DT then
			canVaultTick = 0
			actions.VaultCheck(Plr)
		end
	else
		canVaultTick = 0
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

local function canStartBlock(): boolean
	if not char or not char.Parent then
		return false
	end
	if not hum or hum.Health <= 0 then
		return false
	end
	if not hasSelectedAttackTool(char) then
		return false
	end
	if char:GetAttribute("isBlocking") == true or char:GetAttribute("Parrying") == true then
		return false
	end
	if CombatStateRules.IsDefenseStartBlocked(char, function(stateName)
		return StateManager.GetState(Plr, stateName) == true
	end) then
		return false
	end

	return true
end

local function canUseCritical(): boolean
	if not char or not char.Parent then
		return false
	end
	if not hum or hum.Health <= 0 then
		return false
	end
	if not hasSelectedAttackTool(char) then
		return false
	end
	if blockInputActive or UIS:IsKeyDown(Enum.KeyCode.F) then
		return false
	end
	if char:GetAttribute("HeavyCooldown") == true then
		return false
	end

	if CombatStateRules.IsM1Blocked(char, function(stateName)
		return StateManager.GetState(Plr, stateName) == true
	end) then
		return false
	end

	return true
end

local function canUseSkill(): boolean
	if not char or not char.Parent then
		return false
	end
	if not hum or hum.Health <= 0 then
		return false
	end
	if not hasSelectedAttackTool(char) then
		return false
	end
	if blockInputActive or UIS:IsKeyDown(Enum.KeyCode.F) then
		return false
	end

	if CombatStateRules.IsM1Blocked(char, function(stateName)
		return StateManager.GetState(Plr, stateName) == true
	end) then
		return false
	end

	return true
end

local function onInput(actionName: string, inputState: Enum.UserInputState, _inputObject)
	if actionName == "Mouse2" then
		if inputState == Enum.UserInputState.Begin then
			Settings.Combats.lastMouseButton2Pressed = tick()
		end
		return Enum.ContextActionResult.Pass
	end
	if actionName == "CriticalInput" then
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if not canUseCritical() then
			return Enum.ContextActionResult.Pass
		end

		local now = os.clock()
		if (now - lastCriticalRequestAt) < MIN_LOCAL_CRITICAL_INTERVAL then
			return Enum.ContextActionResult.Sink
		end

		local tool = getSelectedAttackTool(char)
		if not tool then
			return Enum.ContextActionResult.Pass
		end

		lastCriticalRequestAt = now
		actions.Running("Stop", Plr, "None")
		sendCriticalUse()
		return Enum.ContextActionResult.Sink
	end
	local skillKey = SKILL_KEY_BY_ACTION[actionName]
	if skillKey then
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if not canUseSkill() then
			return Enum.ContextActionResult.Pass
		end

		local now = os.clock()
		local lastRequest = lastSkillRequestAt[skillKey] or 0
		if (now - lastRequest) < MIN_LOCAL_SKILL_INTERVAL then
			return Enum.ContextActionResult.Sink
		end

		local tool = getSelectedAttackTool(char)
		if not tool then
			return Enum.ContextActionResult.Pass
		end

		lastSkillRequestAt[skillKey] = now
		actions.Running("Stop", Plr, "None")
		sendSkillUse(skillKey, tool)
		return Enum.ContextActionResult.Sink
	end
	if actionName == "BlockInput" then
		if inputState == Enum.UserInputState.Begin then
			if not canStartBlock() then
				return Enum.ContextActionResult.Pass
			end
			blockInputActive = true
			defenseStopSyncSent = false
			actions.Running("Stop", Plr, "None")
			sendBlockAction(BLOCK_START_PAYLOAD)
			return Enum.ContextActionResult.Sink
		end

		if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			if not blockInputActive then
				return Enum.ContextActionResult.Pass
			end
			blockInputActive = false
			defenseStopSyncSent = true
			sendBlockAction(BLOCK_STOP_PAYLOAD)
			-- Let replicated defense attributes drive the visual stop/start so tap-parry
			-- does not instantly cancel the block animation on key release.
			return Enum.ContextActionResult.Sink
		end

		return Enum.ContextActionResult.Pass
	end

	if inputState == Enum.UserInputState.Begin then
		if isMovementLocked() then
			return
		end
		if actionName == "Dash" then
			if
				blockInputActive
				or UIS:IsKeyDown(Enum.KeyCode.F)
				or isDefenseActive()
				or StateManager.GetState(Plr, StateKeys.Crouching)
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

			if StateManager.GetState(Plr, StateKeys.Swinging) == true then
				actions.Running("Stop", Plr, "None")
				return
			end
			if
				StateManager.GetState(Plr, StateKeys.Blocking) == true
				or StateManager.GetState(Plr, StateKeys.Parrying) == true
			then
				actions.Running("Stop", Plr, "None")
				return
			end

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
	CAS:BindActionAtPriority(
		"CriticalInput",
		onInput,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.R,
		Enum.UserInputType.MouseButton3
	)
	CAS:BindActionAtPriority("SkillInputZ", onInput, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Z)
	CAS:BindActionAtPriority("SkillInputX", onInput, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.X)
	CAS:BindActionAtPriority("SkillInputC", onInput, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.C)
	CAS:BindActionAtPriority("BlockInput", onInput, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.F)
	CAS:BindAction("Dash", onInput, false, Enum.KeyCode.Q)
	CAS:BindActionAtPriority("W", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.W)
	CAS:BindActionAtPriority("A", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.A)
	CAS:BindActionAtPriority("S", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.S)
	CAS:BindActionAtPriority("D", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.D)
	CAS:BindAction("CtrlInput", onInput, false, Enum.KeyCode.LeftControl)
	CAS:BindActionAtPriority("SpaceInput", onInput, false, Enum.ContextActionPriority.Low.Value, Enum.KeyCode.Space)
end

bindInputs()
