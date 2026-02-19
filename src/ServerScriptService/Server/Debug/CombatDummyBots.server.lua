local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local CONFIG = {
	FolderName = "Npcs",
	DefenderName = "DummyDefender",
	Attackers = { "DummyAttacker", "DummyAttacker2" },
	WeaponName = "MSword",
	EnsureFakeTool = true,
	Debug = false,

	DefenderMode = "ParryHold", -- "None", "ParryHold", "BlockHold", "ParryPulse"
	ParryPulseDuration = 0.12,
	ParryPulseEvery = 0.9,

	AttackInterval = 0.14,
	AttackStagger = 0.05,
	AttackDamage = 10,
	AttackCombo = 1,
	TargetPlayers = true,
	TargetDefender = true,
	AutoFaceDefender = false,
	AutoSnapIfFar = false,
	MaxDistanceBeforeSnap = 12,
	AttackDistance = 3.75,
	RequireOverlap = true,
	ForceHitAfterMisses = 0,
	MaxDirectHitDistance = 25,
	ShowHitbox = true,
	HitboxTransparency = 0.35,
	HitboxColor = Color3.fromRGB(255, 80, 80),
	HitboxSize = Vector3.new(6, 6, 5.5),
	HitboxOffset = CFrame.new(0, 0, -4),
}

local function getCombatHandler()
	local serverRoot = ServerScriptService:WaitForChild("Server")
	local handlerRoot = serverRoot:WaitForChild("Handler")
	local combatApi = require(handlerRoot:WaitForChild("Combat"))
	local m1Service = combatApi and combatApi.M1
	if not m1Service then
		return nil
	end
	return m1Service._combatHandler
end

local function ensureNumberValue(parent: Instance, name: string, defaultValue: number): NumberValue
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("NumberValue") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local value = Instance.new("NumberValue")
	value.Name = name
	value.Value = defaultValue
	value.Parent = parent
	return value
end

local function ensureAttributesFolder(character: Model): Folder
	local folder = character:FindFirstChild("Attributes")
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = "Attributes"
	newFolder.Parent = character
	return newFolder
end

local function ensureFakeTool(character: Model, toolName: string)
	local existing = character:FindFirstChild(toolName)
	if existing and existing:IsA("Tool") then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = toolName
	tool:SetAttribute("Type", "Attack")
	tool.Parent = character
end

local function setupDummy(character: Model, weaponName: string, shouldEnsureTool: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return false
	end

	local attrs = ensureAttributesFolder(character)
	ensureNumberValue(attrs, "Posture", 0)
	ensureNumberValue(attrs, "MaxPosture", 100)

	character:SetAttribute("Weapon", weaponName)
	character:SetAttribute("isBlocking", false)
	character:SetAttribute("Parrying", false)
	character:SetAttribute("Combo", 1)
	character:SetAttribute("Swing", false)
	character:SetAttribute("Attacking", false)
	character:SetAttribute("ParrySuccessSerial", 0)

	if shouldEnsureTool then
		ensureFakeTool(character, weaponName)
	end

	return true
end

local function resolveBot(folder: Instance, name: string): Model?
	local model = folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

local function getProxyPlayerName(character: Model): any
	local firstPlayer = Players:GetPlayers()[1]
	if firstPlayer then
		return firstPlayer
	end
	return { Name = character.Name }
end

local function setDefenseState(defender: Model, isBlocking: boolean, isParrying: boolean)
	if not defender or not defender.Parent then
		return
	end
	defender:SetAttribute("isBlocking", isBlocking)
	defender:SetAttribute("Parrying", isParrying)
end

local function steerAttacker(attackerRoot: BasePart, defenderRoot: BasePart, attackerIndex: number)
	local targetAt = Vector3.new(defenderRoot.Position.X, attackerRoot.Position.Y, defenderRoot.Position.Z)
	if CONFIG.AutoFaceDefender then
		attackerRoot.CFrame = CFrame.lookAt(attackerRoot.Position, targetAt)
	end

	local flat = Vector3.new(
		attackerRoot.Position.X - defenderRoot.Position.X,
		0,
		attackerRoot.Position.Z - defenderRoot.Position.Z
	)
	local distance = flat.Magnitude
	local snapDistance = math.max(1, CONFIG.AttackDistance)
	local maxBeforeSnap = math.max(snapDistance, CONFIG.MaxDistanceBeforeSnap)

	if CONFIG.AutoSnapIfFar and distance > maxBeforeSnap then
		local angle = (attackerIndex - 1) * math.rad(18)
		local around = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if around.Magnitude <= 0.001 then
			around = Vector3.new(0, 0, -1)
		end

		local snappedPos = defenderRoot.Position + around.Unit * snapDistance
		snappedPos = Vector3.new(snappedPos.X, attackerRoot.Position.Y, snappedPos.Z)
		attackerRoot.CFrame = CFrame.lookAt(snappedPos, Vector3.new(defenderRoot.Position.X, snappedPos.Y, defenderRoot.Position.Z))
	end
end

local function getDebugFolder(): Folder
	local existing = Workspace:FindFirstChild("DebugHitboxes")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "DebugHitboxes"
	folder.Parent = Workspace
	return folder
end

local function getOrCreateVisualizer(attackerName: string): BasePart
	local folder = getDebugFolder()
	local partName = ("Hitbox_%s"):format(attackerName)
	local existing = folder:FindFirstChild(partName)
	if existing and existing:IsA("BasePart") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local part = Instance.new("Part")
	part.Name = partName
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.ForceField
	part.Color = CONFIG.HitboxColor
	part.Transparency = CONFIG.HitboxTransparency
	part.Parent = folder
	return part
end

local function updateHitboxVisualizer(attackerName: string, cframe: CFrame, size: Vector3)
	if not CONFIG.ShowHitbox then
		return
	end

	local visual = getOrCreateVisualizer(attackerName)
	visual.Size = size
	visual.CFrame = cframe
end

local function makeOverlapParams(attacker: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }
	return params
end

local function collectTouchedCharacters(
	attacker: Model,
	defender: Model,
	hitboxCFrame: CFrame,
	hitboxSize: Vector3
): { Model }
	local touching = Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, makeOverlapParams(attacker))
	local unique = {}
	local result = {}

	local function addCharacter(model: Model)
		if model == attacker then
			return
		end
		if unique[model] then
			return
		end

		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end

		if model == defender then
			if not CONFIG.TargetDefender then
				return
			end
		else
			if not CONFIG.TargetPlayers then
				return
			end
			if not Players:GetPlayerFromCharacter(model) then
				return
			end
		end

		unique[model] = true
		table.insert(result, model)
	end

	for _, part in ipairs(touching) do
		local character = part:FindFirstAncestorOfClass("Model")
		if character then
			addCharacter(character)
		end
	end

	return result
end

local function tryApplyHit(combatHandler: any, attacker: Model, defender: Model, attackerIndex: number): boolean
	if not attacker or not attacker.Parent then
		return false
	end
	if not defender or not defender.Parent then
		return false
	end

	local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
	local defenderRoot = defender:FindFirstChild("HumanoidRootPart")
	local defenderHumanoid = defender:FindFirstChildOfClass("Humanoid")
	if not attackerRoot or not defenderRoot or not defenderHumanoid or defenderHumanoid.Health <= 0 then
		return false
	end

	steerAttacker(attackerRoot, defenderRoot, attackerIndex)

	local hitboxCFrame = attackerRoot.CFrame * CONFIG.HitboxOffset
	updateHitboxVisualizer(attacker.Name, hitboxCFrame, CONFIG.HitboxSize)

	local targets = {}
	if CONFIG.RequireOverlap then
		targets = collectTouchedCharacters(attacker, defender, hitboxCFrame, CONFIG.HitboxSize)
	elseif CONFIG.TargetDefender then
		table.insert(targets, defender)
	end

	if #targets == 0 then
		if CONFIG.Debug then
			warn(("[CombatDummyBots] '%s' no hitbox target."):format(attacker.Name))
		end
		return false
	end

	local attackerPlayer = getProxyPlayerName(attacker)
	for _, targetCharacter in ipairs(targets) do
		combatHandler:ApplyHit(
			attackerPlayer,
			attacker,
			attackerRoot,
			targetCharacter,
			CONFIG.AttackCombo,
			{},
			CONFIG.AttackDamage
		)
	end
	return true
end

local function tryApplyHitDirect(combatHandler: any, attacker: Model, defender: Model): boolean
	if not attacker or not attacker.Parent then
		return false
	end
	if not defender or not defender.Parent then
		return false
	end

	local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
	local defenderRoot = defender:FindFirstChild("HumanoidRootPart")
	local defenderHumanoid = defender:FindFirstChildOfClass("Humanoid")
	if not attackerRoot or not defenderRoot or not defenderHumanoid or defenderHumanoid.Health <= 0 then
		return false
	end

	local flat = Vector3.new(
		attackerRoot.Position.X - defenderRoot.Position.X,
		0,
		attackerRoot.Position.Z - defenderRoot.Position.Z
	)
	if flat.Magnitude > math.max(1, CONFIG.MaxDirectHitDistance) then
		return false
	end

	local attackerPlayer = getProxyPlayerName(attacker)
	combatHandler:ApplyHit(
		attackerPlayer,
		attacker,
		attackerRoot,
		defender,
		CONFIG.AttackCombo,
		{},
		CONFIG.AttackDamage
	)

	if CONFIG.Debug then
		warn(("[CombatDummyBots] '%s' fallback direct hit on '%s'."):format(attacker.Name, defender.Name))
	end

	return true
end

local function runDefenderMode(defender: Model)
	task.spawn(function()
		while defender and defender.Parent do
			local mode = CONFIG.DefenderMode
			if mode == "ParryHold" then
				setDefenseState(defender, false, true)
				task.wait(0.05)
			elseif mode == "BlockHold" then
				setDefenseState(defender, true, false)
				task.wait(0.05)
			elseif mode == "ParryPulse" then
				setDefenseState(defender, false, true)
				task.wait(math.max(0.01, CONFIG.ParryPulseDuration))
				if not defender or not defender.Parent then
					break
				end
				setDefenseState(defender, false, false)
				local restTime = math.max(0.01, CONFIG.ParryPulseEvery - CONFIG.ParryPulseDuration)
				task.wait(restTime)
			else
				setDefenseState(defender, false, false)
				task.wait(0.1)
			end
		end
	end)
end

local function runAttacker(combatHandler: any, attacker: Model, defender: Model, startDelay: number)
	task.spawn(function()
		task.wait(math.max(0, startDelay))
		local attackerIndex = 1
		for i, name in ipairs(CONFIG.Attackers) do
			if name == attacker.Name then
				attackerIndex = i
				break
			end
		end
		local misses = 0

		while attacker and attacker.Parent and defender and defender.Parent do
			local success = tryApplyHit(combatHandler, attacker, defender, attackerIndex)
			if success then
				misses = 0
			else
				misses += 1
				if CONFIG.ForceHitAfterMisses > 0 and misses >= CONFIG.ForceHitAfterMisses then
					if tryApplyHitDirect(combatHandler, attacker, defender) then
						misses = 0
					end
				end
			end
			task.wait(math.max(0.03, CONFIG.AttackInterval))
		end
	end)
end

local botsFolder = Workspace:WaitForChild("Live"):FindFirstChild(CONFIG.FolderName)
if not botsFolder then
	warn(("[CombatDummyBots] Missing folder workspace.%s"):format(CONFIG.FolderName))
	return
end

local defender = resolveBot(botsFolder, CONFIG.DefenderName)
if not defender then
	warn(("[CombatDummyBots] Missing defender '%s'"):format(CONFIG.DefenderName))
	return
end

local attackers = {}
for _, attackerName in ipairs(CONFIG.Attackers) do
	local bot = resolveBot(botsFolder, attackerName)
	if bot then
		table.insert(attackers, bot)
	else
		warn(("[CombatDummyBots] Missing attacker '%s'"):format(attackerName))
	end
end
if #attackers == 0 then
	warn("[CombatDummyBots] No attacker bot found.")
	return
end

local combatHandler = getCombatHandler()
if not combatHandler or typeof(combatHandler.ApplyHit) ~= "function" then
	warn("[CombatDummyBots] Combat handler unavailable.")
	return
end

if not setupDummy(defender, CONFIG.WeaponName, CONFIG.EnsureFakeTool) then
	warn("[CombatDummyBots] Defender is missing Humanoid or HumanoidRootPart.")
	return
end

for _, attacker in ipairs(attackers) do
	if not setupDummy(attacker, CONFIG.WeaponName, CONFIG.EnsureFakeTool) then
		warn(("[CombatDummyBots] Attacker '%s' missing Humanoid or HumanoidRootPart."):format(attacker.Name))
		return
	end
end

runDefenderMode(defender)

for index, attacker in ipairs(attackers) do
	runAttacker(combatHandler, attacker, defender, (index - 1) * CONFIG.AttackStagger)
end

print("[CombatDummyBots] Running in Studio. Edit CONFIG at top of this file.")
