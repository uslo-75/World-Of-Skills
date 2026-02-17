local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local CollisionGroupHandler = {}

CollisionGroupHandler.PlayerGroup = "Players"
CollisionGroupHandler.NoPlayerGroup = "NoPlayerCollision"

local bound = {} -- [Model] = { RBXScriptConnection }
local currentGroup = {} -- [Model] = string

local function ensureGroup(name)
	if PhysicsService.RegisterCollisionGroup then
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	else
		pcall(function()
			PhysicsService:CreateCollisionGroup(name)
		end)
	end
end

local function setCollidable(groupA, groupB, canCollide)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(groupA, groupB, canCollide)
	end)
end

local function applyGroup(character, groupName)
	currentGroup[character] = groupName
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
end

local function bindCharacter(character)
	if bound[character] then
		return
	end

	currentGroup[character] = currentGroup[character] or CollisionGroupHandler.PlayerGroup
	applyGroup(character, currentGroup[character])

	local conns = {}
	conns[1] = character.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") then
			inst.CollisionGroup = currentGroup[character] or CollisionGroupHandler.PlayerGroup
		end
	end)
	conns[2] = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
			bound[character] = nil
			currentGroup[character] = nil
		end
	end)

	bound[character] = conns
end

function CollisionGroupHandler.GetGroup(character)
	if not character then
		return CollisionGroupHandler.PlayerGroup
	end
	return currentGroup[character] or CollisionGroupHandler.PlayerGroup
end

function CollisionGroupHandler.SetGroup(character, groupName)
	if not character or not character.Parent then
		return
	end
	local targetGroup = groupName or CollisionGroupHandler.PlayerGroup
	if targetGroup ~= "Default" then
		ensureGroup(targetGroup)
	end
	if not bound[character] then
		bindCharacter(character)
	end
	applyGroup(character, targetGroup)
end

function CollisionGroupHandler.SetPlayerCollision(character)
	CollisionGroupHandler.SetGroup(character, CollisionGroupHandler.PlayerGroup)
end

function CollisionGroupHandler.SetNoPlayerCollision(character)
	CollisionGroupHandler.SetGroup(character, CollisionGroupHandler.NoPlayerGroup)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(char)
		bindCharacter(char)
	end)

	if player.Character then
		bindCharacter(player.Character)
	end
end

function CollisionGroupHandler.Init()
	if CollisionGroupHandler._initialized then
		return
	end
	CollisionGroupHandler._initialized = true

	ensureGroup(CollisionGroupHandler.PlayerGroup)
	ensureGroup(CollisionGroupHandler.NoPlayerGroup)

	setCollidable(CollisionGroupHandler.PlayerGroup, CollisionGroupHandler.PlayerGroup, true)
	setCollidable(CollisionGroupHandler.PlayerGroup, "Default", true)
	setCollidable(CollisionGroupHandler.NoPlayerGroup, CollisionGroupHandler.PlayerGroup, false)
	setCollidable(CollisionGroupHandler.NoPlayerGroup, CollisionGroupHandler.NoPlayerGroup, false)
	setCollidable(CollisionGroupHandler.NoPlayerGroup, "Default", true)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
end

return CollisionGroupHandler
