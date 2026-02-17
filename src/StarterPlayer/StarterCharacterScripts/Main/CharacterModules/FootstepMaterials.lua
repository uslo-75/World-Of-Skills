local Players = game:GetService("Players")

local FootstepMaterials = {}

local player = Players.LocalPlayer
local characterAddedConn: RBXScriptConnection? = nil
local floorConn: RBXScriptConnection? = nil
local speedConn: RBXScriptConnection? = nil

local function disconnect(conn: RBXScriptConnection?)
	if conn then
		conn:Disconnect()
	end
end

local MaterialSounds = {
	[Enum.Material.Grass] = { SoundId = "rbxassetid://9064714296", Volume = 3, PlaybackSpeed = 1.2 },
	[Enum.Material.Metal] = { SoundId = "rbxassetid://5676620958", Volume = 2, PlaybackSpeed = 1 },
	[Enum.Material.DiamondPlate] = { SoundId = "rbxassetid://944089664", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Pebble] = { SoundId = "rbxassetid://944090255", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Wood] = { SoundId = "rbxassetid://944075408", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.WoodPlanks] = { SoundId = "rbxassetid://944075408", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Plastic] = { SoundId = "rbxassetid://78241561292777", Volume = 1, PlaybackSpeed = 0.75 },
	[Enum.Material.SmoothPlastic] = { SoundId = "rbxassetid://944075408", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Sand] = { SoundId = "rbxassetid://6362185620", Volume = 5, PlaybackSpeed = 1 },
	[Enum.Material.Brick] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Cobblestone] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Concrete] = { SoundId = "rbxassetid://944075408", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.CorrodedMetal] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Fabric] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Foil] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.ForceField] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Glass] = { SoundId = "rbxassetid://944075408", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Granite] = { SoundId = "rbxassetid://944075408", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Ice] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Marble] = { SoundId = "rbxassetid://80027112124187", Volume = 1, PlaybackSpeed = 0.9 },
	[Enum.Material.Neon] = { SoundId = "rbxassetid://4981969796", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Slate] = { SoundId = "rbxassetid://944075408", Volume = 10, PlaybackSpeed = 1 },
	[Enum.Material.Snow] = { SoundId = "rbxassetid://80932364310315", Volume = 2, PlaybackSpeed = 0.75 },
}

local function initForCharacter(character: Model)
	disconnect(floorConn)
	floorConn = nil
	disconnect(speedConn)
	speedConn = nil

	local humanoid = character:WaitForChild("Humanoid")
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	local footStepsSound = humanoidRootPart:WaitForChild("Running", 5)
	if not footStepsSound then
		return
	end

	local baseSpeed = 9

	local function updateForMaterial()
		local floorMaterial = humanoid.FloorMaterial
		local materialConfig = MaterialSounds[floorMaterial]

		baseSpeed = (floorMaterial == Enum.Material.Grass) and 16 or 9

		if materialConfig then
			footStepsSound.Volume = (humanoid.WalkSpeed < 8) and 0 or materialConfig.Volume
			footStepsSound.PlaybackSpeed = materialConfig.PlaybackSpeed * (humanoid.WalkSpeed / baseSpeed)
			footStepsSound.SoundId = materialConfig.SoundId
		else
			footStepsSound.Volume = (humanoid.WalkSpeed < 8) and 0 or 10
			footStepsSound.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
			footStepsSound.PlaybackSpeed = humanoid.WalkSpeed / baseSpeed
		end
	end

	local function updateForSpeed()
		local floorMaterial = humanoid.FloorMaterial
		local materialConfig = MaterialSounds[floorMaterial]

		baseSpeed = (floorMaterial == Enum.Material.Grass) and 16 or 9
		footStepsSound.Volume = (humanoid.WalkSpeed < 8) and 0 or (materialConfig and materialConfig.Volume or 10)

		if materialConfig then
			footStepsSound.PlaybackSpeed = materialConfig.PlaybackSpeed * (humanoid.WalkSpeed / baseSpeed)
		else
			footStepsSound.PlaybackSpeed = humanoid.WalkSpeed / baseSpeed
		end
	end

	updateForMaterial()
	floorConn = humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(updateForMaterial)
	speedConn = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(updateForSpeed)
end

function FootstepMaterials.Init()
	disconnect(characterAddedConn)
	characterAddedConn = nil

	local character = player.Character or player.CharacterAdded:Wait()
	initForCharacter(character)
	characterAddedConn = player.CharacterAdded:Connect(initForCharacter)
end

return FootstepMaterials
