local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationHandler =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("AnimationHandler"))
local MovementBlockStates =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("MovementBlockStates"))
local StateManager
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
	end)
	if ok then
		StateManager = mod
	else
		warn("[BaseAnimator] StateManager unavailable, using fallback:", mod)
		StateManager = {
			GetState = function()
				return false
			end,
		}
	end
end

local player = Players.LocalPlayer
local rng = Random.new()

local DEBUG_BASE_ANIM = false

local BASE_TYPE = "Base"
local BLOCK_STATES = MovementBlockStates.BaseAnimator
local PASS_THROUGH_BASE_STATES = {
	Swinging = true,
	isBlocking = true,
	Parrying = true,
}

local currentConn: RBXScriptConnection? = nil
local currentDiedConn: RBXScriptConnection? = nil

local BASE_TRACK_NAMES = {
	idle = true,
	walk = true,
	run = true,
	jump = true,
	fall = true,
	Landed = true,
	Landing = true,
	FallAnim = true,
	NormalRun = true,
}

local FALL_DELAY = 0.25
local FALL_DELAY_WHILE_RUNNING = 0.8
local FALL_MIN_DOWN_VY = -1
local STOP_FADE = 0.12
local BASE_PRIORITIES = {
	idle = Enum.AnimationPriority.Core,
	walk = Enum.AnimationPriority.Movement,
	run = Enum.AnimationPriority.Movement,
	jump = Enum.AnimationPriority.Movement,
	fall = Enum.AnimationPriority.Movement,
}

local function getBasePriority(desired: string?): Enum.AnimationPriority
	if desired and BASE_PRIORITIES[desired] then
		return BASE_PRIORITIES[desired]
	end
	return Enum.AnimationPriority.Movement
end

local function findAnimationByNames(folder: Instance?, names: { string }): Animation?
	if not folder then
		return nil
	end

	for _, name in ipairs(names) do
		local direct = folder:FindFirstChild(name)
		if direct and direct:IsA("Animation") then
			return direct
		end
	end

	local wantedLower = {}
	for _, name in ipairs(names) do
		wantedLower[string.lower(name)] = true
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Animation") and wantedLower[string.lower(child.Name)] then
			return child
		end
	end

	return nil
end

local function isBlocked(plr: Player): boolean
	for _, stateName in ipairs(BLOCK_STATES) do
		if not PASS_THROUGH_BASE_STATES[stateName] and StateManager.GetState(plr, stateName) == true then
			return true
		end
	end
	return false
end

local function pickWeightedAnimId(holder: Instance?): string?
	if not holder then
		return nil
	end

	local entries = {}
	local total = 0
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Animation") then
			local weight = 1
			local w = child:FindFirstChild("Weight")
			if w and w:IsA("NumberValue") then
				weight = w.Value
			end
			total += weight
			table.insert(entries, { anim = child, weight = weight })
		end
	end

	if #entries == 0 then
		return nil
	end

	local roll = rng:NextNumber(0, total)
	for _, entry in ipairs(entries) do
		roll -= entry.weight
		if roll <= 0 then
			return entry.anim.AnimationId
		end
	end

	return entries[1].anim.AnimationId
end

local function getEquippedToolName(char: Model): string?
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then
		return nil
	end
	if tool:GetAttribute("Type") ~= "Attack" then
		return nil
	end
	if not tool:FindFirstChild("EquipedWeapon") then
		return nil
	end

	local weaponAttr = tool:GetAttribute("Weapon")
	if typeof(weaponAttr) == "string" and weaponAttr ~= "" then
		return weaponAttr
	end

	return tool.Name
end

local function resolveAnimId(desired: string, toolName: string?, animate: Instance?, assetsRoot: Instance?): string?
	if assetsRoot then
		local animRoot = assetsRoot:FindFirstChild("animation")
		if animRoot then
			-- weapon-specific (combat)
			-- Keep base walk/idle generic so weapon idle overlay can layer consistently.
			if toolName and desired ~= "walk" and desired ~= "idle" then
				local combat = animRoot:FindFirstChild("combat")
				local toolFolder = combat and combat:FindFirstChild(toolName)
				local desiredNames = { desired, desired:sub(1, 1):upper() .. desired:sub(2) }
				if desired == "run" then
					desiredNames = { "NormalRun", "Run", "run" }
				elseif desired == "walk" then
					desiredNames = { "Walk", "walk" }
				elseif desired == "idle" then
					desiredNames = { "Idle", "idle" }
				end
				local animObj = findAnimationByNames(toolFolder, desiredNames)
				if animObj then
					return animObj.AnimationId
				end
			end

			-- generic move folder
			local move = animRoot:FindFirstChild("move")
			local moveNames = { desired }
			if desired == "run" then
				moveNames = { "NormalRun", "Run", "run" }
			elseif desired == "fall" then
				moveNames = { "FallAnim", "Fall", "fall" }
			elseif desired == "jump" then
				moveNames = { "Jump", "jump" }
			elseif desired == "walk" then
				moveNames = { "Walk", "walk" }
			elseif desired == "idle" then
				moveNames = { "Idle", "idle" }
			end
			local moveAnim = findAnimationByNames(move, moveNames)
			if moveAnim then
				return moveAnim.AnimationId
			end
		end
	end

	-- fallback to default Animate container
	local holder = animate
		and (animate:FindFirstChild(desired) or animate:FindFirstChild(desired:sub(1, 1):upper() .. desired:sub(2)))
	return pickWeightedAnimId(holder)
end

local function setupBaseAnimations(character: Model)
	if currentConn then
		currentConn:Disconnect()
		currentConn = nil
	end
	if currentDiedConn then
		currentDiedConn:Disconnect()
		currentDiedConn = nil
	end

	local humanoid = character:WaitForChild("Humanoid")
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 5)
	local assetsRoot = ReplicatedStorage:FindFirstChild("Assets")

	if animate and animate:IsA("LocalScript") and animate ~= script then
		animate.Disabled = true
	end
	if animate == script then
		animate = nil
	end

	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		track:Stop(0)
		pcall(function()
			track:Destroy()
		end)
	end

	local currentBaseName: string? = nil
	local currentAnimId: string? = nil
	local currentTrack: AnimationTrack? = nil
	local currentKey: string? = nil
	local lastDesired: string? = nil
	local lastDebugKey: string? = nil
	local lastDebugState: Enum.HumanoidStateType? = nil
	local lastClimbing = false
	local lastBlocked = false
	local lastDowned = false
	local wasAirborne = false
	local airStartTime = 0

	local function debugLog(state: Enum.HumanoidStateType, desired: string?, toolName: string?, animId: string?)
		if not DEBUG_BASE_ANIM then
			return
		end
		local s = state.Name
		local key = tostring(desired)
			.. "|"
			.. tostring(toolName or "none")
			.. "|"
			.. tostring(animId or "nil")
			.. "|"
			.. s
		if key == lastDebugKey then
			return
		end
		lastDebugKey = key
		lastDebugState = state
		print(
			("[BaseAnimator] state=%s desired=%s tool=%s animId=%s"):format(
				s,
				tostring(desired),
				tostring(toolName),
				tostring(animId)
			)
		)
	end

	local function stopBaseTracks()
		for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
			if BASE_TRACK_NAMES[track.Name] then
				track:Stop(0)
			end
		end
	end

	local function stopAllTracks(fadeTime: number?, exceptName: string?)
		for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
			if not exceptName or track.Name ~= exceptName then
				track:Stop(fadeTime or 0)
			end
		end
	end

	local function getTrackIsPlaying(track: AnimationTrack?): boolean?
		if not track then
			return nil
		end
		local ok, playing = pcall(function()
			return track.IsPlaying
		end)
		if not ok then
			return nil
		end
		return playing == true
	end

	local function resetBaseState()
		if currentAnimId then
			AnimationHandler.StopAnims(character, BASE_TYPE)
		end
		currentBaseName = nil
		currentAnimId = nil
		currentTrack = nil
		currentKey = nil
		lastDesired = nil
	end

	local function stopAllBase()
		stopBaseTracks()
		AnimationHandler.StopAnims(character, BASE_TYPE)
		resetBaseState()
	end

	currentDiedConn = humanoid.Died:Connect(function()
		stopAllBase()
	end)

	local function update()
		if not character.Parent or humanoid.Health <= 0 then
			stopAllBase()
			return
		end

		if StateManager.GetState(player, "Downed") == true then
			local isCarried = character:GetAttribute("Carried") == true
			if isCarried then
				stopAllTracks(STOP_FADE, "Carried")
			else
				stopAllTracks(STOP_FADE)
			end
			resetBaseState()
			lastDowned = true
			return
		elseif lastDowned then
			lastDowned = false
		end

		local state = humanoid:GetState()
		local now = time()
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
		if airborne then
			if not wasAirborne then
				airStartTime = now
			end
		else
			airStartTime = 0
		end
		if wasAirborne and not airborne then
			for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
				if track.Name == "jump" or track.Name == "fall" then
					track:Stop(STOP_FADE)
				end
			end
		end
		wasAirborne = airborne

		if state == Enum.HumanoidStateType.Ragdoll or character:GetAttribute("IsRagdoll") == true then
			resetBaseState()
			return
		end

		if state == Enum.HumanoidStateType.Climbing then
			if not lastClimbing then
				stopBaseTracks()
				resetBaseState()
			end
			lastClimbing = true
			debugLog(state, "climb_block", nil, nil)
			return
		end
		lastClimbing = false

		if isBlocked(player) then
			if not lastBlocked then
				stopBaseTracks()
				resetBaseState()
			end
			lastBlocked = true
			debugLog(state, "blocked", nil, nil)
			return
		end
		lastBlocked = false

		local desired: string?
		local moving = false
		if hrp then
			local v = hrp.AssemblyLinearVelocity
			local horizSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
			moving = horizSpeed > 0.2
		else
			moving = humanoid.MoveDirection.Magnitude > 0.05
		end

		local runningState = StateManager.GetState(player, "Running") == true
		local fallEligible = false
		if airborne and airStartTime > 0 then
			local needed = runningState and FALL_DELAY_WHILE_RUNNING or FALL_DELAY
			if (now - airStartTime) >= needed then
				fallEligible = true
				if hrp then
					local vy = hrp.AssemblyLinearVelocity.Y
					if vy > FALL_MIN_DOWN_VY then
						fallEligible = false
					end
				end
			end
		end

		if runningState then
			-- If running, keep run until long fall threshold triggers
			if fallEligible then
				-- force stop run only when transitioning to fall (avoid stopping every frame)
				if currentBaseName ~= "fall" then
					stopBaseTracks()
					resetBaseState()
				end
				desired = "fall"
			else
				desired = moving and "run" or "idle"
			end
		else
			if not fallEligible and (state == Enum.HumanoidStateType.Jumping or airborne) then
				desired = "jump"
			elseif
				state == Enum.HumanoidStateType.Freefall
				or state == Enum.HumanoidStateType.FallingDown
				or fallEligible
			then
				desired = "fall"
			else
				if moving then
					desired = "walk"
				else
					desired = "idle"
				end
			end
		end

		local toolName = getEquippedToolName(character)
		local key = desired .. "|" .. tostring(toolName or "none")
		local resolvedAnimId = resolveAnimId(desired, toolName, animate, assetsRoot)
		local desiredPriority = getBasePriority(desired)

		local transitionedToIdleWalk = (desired == "idle" or desired == "walk") and desired ~= lastDesired
		if transitionedToIdleWalk then
			for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
				if track.Name == "jump" or track.Name == "fall" or track.Name == "run" then
					track:Stop(STOP_FADE)
				end
			end
		end
		lastDesired = desired

		if currentTrack then
			local playing = getTrackIsPlaying(currentTrack)
			if playing == nil then
				currentTrack = nil
				currentAnimId = nil
				currentBaseName = nil
				currentKey = nil
			end
		end

		if key ~= currentKey then
			local canKeepCurrent = resolvedAnimId ~= nil and currentAnimId == resolvedAnimId and currentTrack ~= nil

			if canKeepCurrent then
				currentKey = key
				currentBaseName = desired
				if currentTrack then
					currentTrack.Priority = desiredPriority
				end

				if getTrackIsPlaying(currentTrack) == false then
					pcall(function()
						currentTrack:Play()
					end)
				end
			else
				AnimationHandler.StopAnims(character, BASE_TYPE)
				currentBaseName = nil
				currentAnimId = nil
				currentTrack = nil
				currentKey = key

				if resolvedAnimId then
					currentBaseName = desired
					currentAnimId = resolvedAnimId
					currentTrack = AnimationHandler.LoadAnim(character, BASE_TYPE, resolvedAnimId, nil, {
						replaceType = true,
						priority = desiredPriority,
					})
					if currentTrack then
						currentTrack.Name = desired
					end
				end
			end

			debugLog(state, desired, toolName, currentAnimId)
		elseif currentTrack and getTrackIsPlaying(currentTrack) == false then
			pcall(function()
				currentTrack:Play()
			end)
			debugLog(state, desired, toolName, currentAnimId)
		end

		if currentTrack and currentBaseName == "run" then
			local airborne = state == Enum.HumanoidStateType.Freefall
				or state == Enum.HumanoidStateType.Jumping
				or state == Enum.HumanoidStateType.FallingDown
			currentTrack:AdjustSpeed(airborne and 0.32 or 1)
		end
	end

	currentConn = RunService.Heartbeat:Connect(update)
	update()
end

if player.Character then
	setupBaseAnimations(player.Character)
end
player.CharacterAdded:Connect(setupBaseAnimations)
