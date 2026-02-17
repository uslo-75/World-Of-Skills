local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local StatsService = require(script.Parent:WaitForChild("StatsService"))
local StateManager =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local RegenConfig = require(script.Parent:WaitForChild("RegenConfig"))
local RegenRules = require(script.Parent:WaitForChild("RegenRules"))

local RegenService = {}

RegenService.Config = RegenConfig

local Rules = RegenRules.new({
	Config = RegenService.Config,
	CollectionService = CollectionService,
	StateManager = StateManager,
})

local nextRegenAt: { [Player]: number } = {}
local boundCharacters: { [Model]: { RBXScriptConnection } } = {}
local lastKnownHealth: { [Humanoid]: number } = setmetatable({}, { __mode = "k" })

local regenAccumulator = 0
local heartbeatConn: RBXScriptConnection? = nil

local function getHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getAttributesFolder(player: Player, createIfMissing: boolean?): Folder?
	local folder = player:FindFirstChild(RegenService.Config.AttributesFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if createIfMissing ~= true then
		return nil
	end

	if folder ~= nil then
		folder:Destroy()
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = RegenService.Config.AttributesFolderName
	newFolder.Parent = player
	return newFolder
end

local function ensureNumberValue(folder: Folder, valueName: string, defaultValue: number): (NumberValue, boolean)
	local valueObject = folder:FindFirstChild(valueName)
	local created = false

	if not valueObject or not valueObject:IsA("NumberValue") then
		if valueObject ~= nil then
			valueObject:Destroy()
		end
		valueObject = Instance.new("NumberValue")
		valueObject.Name = valueName
		valueObject.Value = defaultValue
		valueObject.Parent = folder
		created = true
	end

	return valueObject, created
end

local function syncEtherValues(player: Player, resolvedStats): (NumberValue?, NumberValue?, number)
	local maxEther = math.max(0, tonumber(resolvedStats.MaxEther) or 0)
	local attributes = getAttributesFolder(player, true)
	if not attributes then
		return nil, nil, maxEther
	end

	local maxEtherValue = ensureNumberValue(attributes, RegenService.Config.MaxEtherValueName, maxEther)
	maxEtherValue.Value = maxEther

	local etherValue, createdEther = ensureNumberValue(attributes, RegenService.Config.EtherValueName, maxEther)
	if createdEther then
		etherValue.Value = maxEther
	else
		etherValue.Value = math.clamp(etherValue.Value, 0, maxEther)
	end

	return etherValue, maxEtherValue, maxEther
end

local function debugHealthRegen(player: Player, humanoid: Humanoid, hpAdded: number, downed: boolean, inCombat: boolean)
	if RegenService.Config.DebugHealthRegen ~= true then
		return
	end
	if hpAdded <= 0 then
		return
	end

	local pctOfMax = (humanoid.MaxHealth > 0) and ((hpAdded / humanoid.MaxHealth) * 100) or 0
	print(
		string.format(
			"[RegenDebug] %s +%.3f HP (%.3f%% MaxHP) [downed=%s combat=%s]",
			player.Name,
			hpAdded,
			pctOfMax,
			tostring(downed),
			tostring(inCombat)
		)
	)
end

local function applyHealthRegenStep(
	player: Player,
	character: Model,
	humanoid: Humanoid,
	resolvedStats,
	step: number,
	inCombat: boolean,
	downed: boolean
)
	if Rules.IsRegenBlockedCommon(player, character, humanoid) then
		return
	end
	if humanoid.Health >= humanoid.MaxHealth then
		return
	end

	-- Downed recovery is normalized: same time to recover 5% for every MaxHP.
	if downed then
		local recoverRatio = math.clamp(RegenService.Config.DownedExitRatio, 0, 1)
		local recoverSeconds = math.max(0.05, RegenService.Config.DownedRecoverSeconds)
		local regenAmount = (humanoid.MaxHealth * recoverRatio / recoverSeconds) * step
		if regenAmount <= 0 then
			return
		end
		local before = humanoid.Health
		humanoid.Health = math.min(humanoid.Health + regenAmount, humanoid.MaxHealth)
		debugHealthRegen(player, humanoid, humanoid.Health - before, downed, inCombat)
		return
	end

	local regenPercent = resolvedStats.HPRegenPercent
	if inCombat then
		regenPercent *= resolvedStats.HPRegenCombatScale
	end

	local regenAmount = (humanoid.MaxHealth * regenPercent + resolvedStats.HPRegenFlat) * step
	if regenAmount <= 0 then
		return
	end

	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.Health + regenAmount, humanoid.MaxHealth)
	debugHealthRegen(player, humanoid, humanoid.Health - before, downed, inCombat)
end

local function applyEtherRegenStep(
	player: Player,
	character: Model,
	humanoid: Humanoid,
	resolvedStats,
	step: number,
	inCombat: boolean,
	downed: boolean,
	etherValue: NumberValue?,
	maxEther: number?
)
	if Rules.IsRegenBlockedCommon(player, character, humanoid) then
		return
	end

	local currentEther = etherValue
	local currentMaxEther = maxEther
	if currentEther == nil or currentMaxEther == nil then
		currentEther, _, currentMaxEther = syncEtherValues(player, resolvedStats)
	end

	currentMaxEther = math.max(0, tonumber(currentMaxEther) or 0)
	if not currentEther or currentMaxEther <= 0 then
		return
	end
	if currentEther.Value >= currentMaxEther then
		return
	end

	local regenPercent = downed and resolvedStats.DownedEtherRegenPercent or resolvedStats.EtherRegenPercent
	if inCombat then
		regenPercent *= resolvedStats.EtherRegenCombatScale
	end

	local regenAmount = (currentMaxEther * regenPercent + resolvedStats.EtherRegenFlat) * step
	if regenAmount <= 0 then
		return
	end

	currentEther.Value = math.min(currentEther.Value + regenAmount, currentMaxEther)
end

local function applyRegenStep(player: Player, step: number)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end

	local now = os.clock()
	local nextAllowed = nextRegenAt[player]
	if nextAllowed and now < nextAllowed then
		return
	end

	local resolved = StatsService.ResolvePlayerStats(player)
	StatsService.RefreshHumanoidMaxHealth(player, humanoid, resolved)
	local etherValue, _, maxEther = syncEtherValues(player, resolved)

	local inCombat = Rules.IsInCombat(player, character)
	local downed = Rules.IsDowned(player, character)

	applyHealthRegenStep(player, character, humanoid, resolved, step, inCombat, downed)
	applyEtherRegenStep(player, character, humanoid, resolved, step, inCombat, downed, etherValue, maxEther)
end

local function unbindCharacter(character: Model)
	local conns = boundCharacters[character]
	if not conns then
		return
	end

	for _, conn in ipairs(conns) do
		conn:Disconnect()
	end
	boundCharacters[character] = nil
end

local function trackHumanoidDamage(player: Player, humanoid: Humanoid)
	lastKnownHealth[humanoid] = humanoid.Health

	return humanoid.HealthChanged:Connect(function(newHealth)
		local previous = lastKnownHealth[humanoid]
		lastKnownHealth[humanoid] = newHealth
		if previous == nil then
			return
		end
		if newHealth < previous then
			RegenService.MarkDamaged(player)
		end
	end)
end

function RegenService.RegisterCharacter(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	unbindCharacter(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 10)
	end
	if not humanoid then
		return
	end

	local resolved = StatsService.ResolvePlayerStats(player)
	StatsService.RefreshHumanoidMaxHealth(player, humanoid, resolved)
	syncEtherValues(player, resolved)

	local conns = {}
	conns[1] = trackHumanoidDamage(player, humanoid)
	conns[2] = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unbindCharacter(character)
		end
	end)
	conns[3] = humanoid.Died:Connect(function()
		lastKnownHealth[humanoid] = nil
		nextRegenAt[player] = nil
	end)

	boundCharacters[character] = conns
end

function RegenService.MarkDamaged(player: Player, delayOverride: number?)
	if not player then
		return
	end

	local delay = tonumber(delayOverride)
	if delay == nil then
		local resolved = StatsService.ResolvePlayerStats(player)
		delay = resolved.RegenDelay
	end

	delay = math.max(0, delay or 0)
	if delay <= 0 then
		nextRegenAt[player] = nil
		return
	end

	nextRegenAt[player] = os.clock() + delay
end

function RegenService.MarkDamagedFromHumanoid(humanoid: Humanoid?, delayOverride: number?)
	if not humanoid or not humanoid.Parent then
		return
	end

	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	if player then
		RegenService.MarkDamaged(player, delayOverride)
	end
end

function RegenService.GetEther(player: Player): (number?, number?)
	local attributes = getAttributesFolder(player, false)
	if not attributes then
		return nil, nil
	end

	local etherValue = attributes:FindFirstChild(RegenService.Config.EtherValueName)
	local maxEtherValue = attributes:FindFirstChild(RegenService.Config.MaxEtherValueName)

	local current = (etherValue and etherValue:IsA("NumberValue")) and etherValue.Value or nil
	local max = (maxEtherValue and maxEtherValue:IsA("NumberValue")) and maxEtherValue.Value or nil
	return current, max
end

function RegenService.SetEther(player: Player, newValue: number): number?
	if typeof(newValue) ~= "number" then
		return nil
	end

	local resolved = StatsService.ResolvePlayerStats(player)
	local etherValue, _, maxEther = syncEtherValues(player, resolved)
	if not etherValue then
		return nil
	end

	etherValue.Value = math.clamp(newValue, 0, maxEther)
	return etherValue.Value
end

function RegenService.AddEther(player: Player, amount: number): number?
	if typeof(amount) ~= "number" or amount == 0 then
		local current = select(1, RegenService.GetEther(player))
		return current
	end

	local current = select(1, RegenService.GetEther(player))
	if current == nil then
		local resolved = StatsService.ResolvePlayerStats(player)
		syncEtherValues(player, resolved)
		current = select(1, RegenService.GetEther(player))
	end
	if current == nil then
		return nil
	end

	return RegenService.SetEther(player, current + amount)
end

function RegenService.ApplyKillReward(player: Player, healthPercent: number?, etherPercent: number?)
	if not player then
		return
	end

	local hpPct = math.max(0, tonumber(healthPercent) or 0)
	local etherPct = math.max(0, tonumber(etherPercent) or 0)
	if hpPct <= 0 and etherPct <= 0 then
		return
	end

	local character = player.Character
	local humanoid = getHumanoid(character)

	if humanoid and humanoid.Health > 0 and hpPct > 0 then
		StatsService.RefreshHumanoidMaxHealth(player, humanoid)
		humanoid.Health = math.min(humanoid.Health + (humanoid.MaxHealth * hpPct), humanoid.MaxHealth)
	end

	if etherPct > 0 then
		local resolved = StatsService.ResolvePlayerStats(player)
		local etherValue, _, maxEther = syncEtherValues(player, resolved)
		if etherValue and maxEther > 0 then
			etherValue.Value = math.min(etherValue.Value + (maxEther * etherPct), maxEther)
		end
	end
end

function RegenService.Init()
	if RegenService._initialized then
		return
	end
	RegenService._initialized = true

	StatsService.Init()

	local function bindPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			RegenService.RegisterCharacter(character)
		end)

		if player.Character then
			RegenService.RegisterCharacter(player.Character)
		else
			local resolved = StatsService.ResolvePlayerStats(player)
			syncEtherValues(player, resolved)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		nextRegenAt[player] = nil

		local character = player.Character
		if character then
			unbindCharacter(character)
		end
	end)

	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		regenAccumulator += dt
		local tickRate = math.max(0.05, tonumber(RegenService.Config.TickRate) or 0.25)
		local step = tonumber(RegenService.Config.StepSeconds)
		if step == nil or step <= 0 then
			step = tickRate
		end

		while regenAccumulator >= tickRate do
			regenAccumulator -= tickRate
			for _, player in ipairs(Players:GetPlayers()) do
				applyRegenStep(player, step)
			end
		end
	end)
end

return RegenService
