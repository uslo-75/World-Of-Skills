local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local MovementBlockStates =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("MovementBlockStates"))

local DirectionalWalk = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ROTATE_SPEED = 12
local LEAN_ANGLE = 14
local LEAN_SPEED = 8

local BLOCK_STATES = MovementBlockStates.DirectionalWalk

local character: Model?
local humanoid: Humanoid?
local rootPart: BasePart?
local rootJoint: Motor6D?
local origC0: CFrame?

local currentLeanX, currentLeanZ = 0, 0
local renderConn: RBXScriptConnection? = nil
local characterAddedConn: RBXScriptConnection? = nil

local function disconnect(conn: RBXScriptConnection?)
	if conn then
		conn:Disconnect()
	end
end

local function bindCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart")
	rootJoint = rootPart:FindFirstChild("RootJoint")
	origC0 = rootJoint and rootJoint.C0 or nil
end

local function resetLean()
	currentLeanX, currentLeanZ = 0, 0
	if rootJoint and origC0 then
		rootJoint.C0 = origC0
	end
end

local function shouldSuppress(): boolean
	if not character or not character.Parent then
		return true
	end
	if not humanoid or not humanoid.Parent then
		return true
	end
	if humanoid.Health <= 0 then
		return true
	end
	if UserInputService:GetFocusedTextBox() then
		return true
	end
	if StateManager.GetState(player, "IsRagdoll") == true then
		return true
	end
	if StateManager.GetState(player, "Downed") == true then
		return true
	end
	if character:GetAttribute("IsRagdoll") then
		return true
	end
	if character:GetAttribute("Downed") then
		return true
	end
	if humanoid.PlatformStand then
		return true
	end
	if humanoid.AutoRotate == false then
		return true
	end
	for _, stateKey in ipairs(BLOCK_STATES) do
		if StateManager.GetState(player, stateKey) then
			return true
		end
	end
	return false
end

function DirectionalWalk.Init()
	disconnect(characterAddedConn)
	characterAddedConn = nil
	disconnect(renderConn)
	renderConn = nil

	if player.Character then
		bindCharacter(player.Character)
	end
	characterAddedConn = player.CharacterAdded:Connect(bindCharacter)

	renderConn = RunService.RenderStepped:Connect(function(dt)
		if shouldSuppress() then
			resetLean()
			return
		end

		local shiftlock = (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter)
		if not shiftlock then
			resetLean()
			return
		end

		if not rootPart or not humanoid then
			resetLean()
			return
		end

		local camCF = camera.CFrame
		local camLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		if camLook.Magnitude > 0 then
			camLook = camLook.Unit
			local targetCF = CFrame.new(rootPart.Position, rootPart.Position + camLook)
			rootPart.CFrame = rootPart.CFrame:Lerp(targetCF, math.clamp(ROTATE_SPEED * dt, 0, 1))
		end

		local moveDir = humanoid.MoveDirection
		local camRight = camCF.RightVector
		local camFwd = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		if camFwd.Magnitude > 0 then
			camFwd = camFwd.Unit
		end
		local inputX = moveDir:Dot(camRight)
		local inputZ = moveDir:Dot(camFwd)

		local targetLeanX = -inputX * LEAN_ANGLE
		local targetLeanZ = inputZ * (LEAN_ANGLE * 0.5)

		currentLeanX += (targetLeanX - currentLeanX) * math.clamp(LEAN_SPEED * dt, 0, 1)
		currentLeanZ += (targetLeanZ - currentLeanZ) * math.clamp(LEAN_SPEED * dt, 0, 1)

		if rootJoint and origC0 then
			rootJoint.C0 = origC0 * CFrame.Angles(math.rad(currentLeanZ), 0, math.rad(currentLeanX))
		end
	end)
end

return DirectionalWalk
