local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ModifierService = require(script.Parent:WaitForChild("ModifierService"))

local StatsService = {}

StatsService.Config = {
	BaseMaxHP = 80,
	BaseMaxEther = 50,
	VitalityToMaxHP = 1.25,
	IntelligenceToMaxEther = 1,
	CacheLifetime = 0.2, -- short cache window to avoid duplicated resolves in same regen loop
	BaseHPRegenPercent = 0.1, -- 10% of max health per tick
	DownedHPRegenPercent = 0.0025, -- only used as fallback (Downed HP is normalized in RegenService)
	BaseEtherRegenPercent = 0.05, -- 5% of max ether per second
	DownedEtherRegenPercent = 0.015, -- 1.5% of max ether per second
	BaseHPRegenFlat = 0,
	BaseEtherRegenFlat = 0,
	BaseRegenDelay = 0, -- seconds after taking damage
	BaseHPRegenCombatScale = 0.2, -- regen multiplier while Combat-tagged
	BaseEtherRegenCombatScale = 0.5, -- ether regen multiplier while in combat
}

export type ResolvedStats = {
	MaxHP: number,
	MaxEther: number,
	HPRegenPercent: number,
	DownedHPRegenPercent: number,
	HPRegenFlat: number,
	EtherRegenPercent: number,
	DownedEtherRegenPercent: number,
	EtherRegenFlat: number,
	RegenDelay: number,
	HPRegenCombatScale: number,
	EtherRegenCombatScale: number,
}

type CacheEntry = {
	stats: ResolvedStats,
	expiresAt: number,
}

local cache: { [Player]: CacheEntry } = {}
local dataManagerCache = nil
local dataManagerFailed = false

local function invalidatePlayer(player: Player)
	cache[player] = nil
end

local function getDataManager()
	if dataManagerCache ~= nil then
		return dataManagerCache
	end
	if dataManagerFailed then
		return nil
	end

	local ok, result = pcall(function()
		return require(
			ServerScriptService:WaitForChild("Server")
				:WaitForChild("Data")
				:WaitForChild("PlayerManager")
				:WaitForChild("DataManager")
		)
	end)

	if ok then
		dataManagerCache = result
		return dataManagerCache
	end

	dataManagerFailed = true
	warn("[StatsService] Could not load DataManager:", result)
	return nil
end

local function getProfileCharStats(player: Player)
	local dataManager = getDataManager()
	if not dataManager or not dataManager.Profiles then
		return nil
	end

	local profile = dataManager.Profiles[player]
	if not profile or not profile.Data then
		return nil
	end

	local selectedSlot = profile.Data.SelectedSlot
	if selectedSlot == nil then
		return nil
	end

	local slotData = profile.Data[selectedSlot]
	if not slotData or not slotData.CharStats then
		return nil
	end

	return slotData.CharStats
end

local function getNumericFromValueFolders(player: Player, statName: string): number?
	local attributesFolder = player:FindFirstChild("Attributes")
	local fromAttributes = attributesFolder and attributesFolder:FindFirstChild(statName)
	if fromAttributes and fromAttributes:IsA("NumberValue") then
		return fromAttributes.Value
	end

	local statsFolder = player:FindFirstChild("Stats")
	local fromStats = statsFolder and statsFolder:FindFirstChild(statName)
	if fromStats and fromStats:IsA("NumberValue") then
		return fromStats.Value
	end

	return nil
end

local function getNumericFromStatsFolder(player: Player, statName: string): number?
	local statsFolder = player:FindFirstChild("Stats")
	local valueObject = statsFolder and statsFolder:FindFirstChild(statName)
	if valueObject and valueObject:IsA("NumberValue") then
		return valueObject.Value
	end
	return nil
end

local function readBaseStat(player: Player, charStats, key: string, defaultValue: number): number
	local v = nil
	v = getNumericFromValueFolders(player, key)
	if v == nil and charStats ~= nil then
		v = tonumber(charStats[key])
	end
	if v == nil then
		return defaultValue
	end
	return v
end

local function readDerivedStat(player: Player, key: string, defaultValue: number): number
	local v = getNumericFromStatsFolder(player, key)
	if v == nil then
		return defaultValue
	end
	return v
end

local function getBaseStats(player: Player): ResolvedStats
	local cfg = StatsService.Config
	local charStats = getProfileCharStats(player)

	local hpBuff = readBaseStat(player, charStats, "HPBuff", 0)
	local etherBuff = readBaseStat(player, charStats, "EtherBuff", 0)
	local vitality = readBaseStat(player, charStats, "Vitality", 0)
	local intelligence = readBaseStat(player, charStats, "Intelligence", 0)
	local maxHpBase = readBaseStat(player, charStats, "MaxHP", cfg.BaseMaxHP)
	local maxEtherBase = readBaseStat(player, charStats, "MaxEther", cfg.BaseMaxEther)

	local maxHp = maxHpBase + (vitality * cfg.VitalityToMaxHP) + hpBuff
	local maxEther = maxEtherBase + (intelligence * cfg.IntelligenceToMaxEther) + etherBuff
	local vitalityMul = math.max(0, readDerivedStat(player, "VitalityMul", 1))
	local intelMul = math.max(0, readDerivedStat(player, "IntelMul", 1))
	local hpRegenMul = math.max(0, readDerivedStat(player, "HPRegenMul", vitalityMul))
	local etherRegenMul = math.max(0, readDerivedStat(player, "EtherRegenMul", intelMul))
	local downedHpRegenMul = math.max(0, readDerivedStat(player, "DownedHPRegenMul", hpRegenMul))
	local downedEtherRegenMul = math.max(0, readDerivedStat(player, "DownedEtherRegenMul", etherRegenMul))
	local hpCombatScale = math.max(0, readDerivedStat(player, "HPRegenCombatScale", cfg.BaseHPRegenCombatScale))
	local etherCombatScale =
		math.max(0, readDerivedStat(player, "EtherRegenCombatScale", cfg.BaseEtherRegenCombatScale))

	local hpRegen = cfg.BaseHPRegenPercent * hpRegenMul
	local downedHpRegen = cfg.DownedHPRegenPercent * downedHpRegenMul
	local etherRegen = cfg.BaseEtherRegenPercent * etherRegenMul
	local downedEtherRegen = cfg.DownedEtherRegenPercent * downedEtherRegenMul

	return {
		MaxHP = maxHp,
		MaxEther = maxEther,
		HPRegenPercent = hpRegen,
		DownedHPRegenPercent = downedHpRegen,
		HPRegenFlat = cfg.BaseHPRegenFlat,
		EtherRegenPercent = etherRegen,
		DownedEtherRegenPercent = downedEtherRegen,
		EtherRegenFlat = cfg.BaseEtherRegenFlat,
		RegenDelay = cfg.BaseRegenDelay,
		HPRegenCombatScale = hpCombatScale,
		EtherRegenCombatScale = etherCombatScale,
	}
end

local function applyModifiers(player: Player, stats: ResolvedStats): ResolvedStats
	local mods = ModifierService.GetModifiers(player)
	if #mods == 0 then
		return stats
	end

	local addByStat = {}
	local mulByStat = {}
	local overrideByStat = {}

	for _, mod in ipairs(mods) do
		local statName = mod.stat
		if stats[statName] ~= nil then
			local stacks = math.max(1, tonumber(mod.stacks) or 1)
			local value = tonumber(mod.value) or 0

			if mod.mode == "Add" then
				addByStat[statName] = (addByStat[statName] or 0) + (value * stacks)
			elseif mod.mode == "Mul" then
				local acc = mulByStat[statName] or 1
				for _ = 1, stacks do
					acc *= value
				end
				mulByStat[statName] = acc
			elseif mod.mode == "Override" then
				overrideByStat[statName] = {
					value = value,
					addedAt = mod.addedAt or 0,
				}
			end
		end
	end

	local resolved = table.clone(stats)
	for statName, baseValue in pairs(resolved) do
		local value = baseValue
		value += addByStat[statName] or 0
		value *= mulByStat[statName] or 1

		local override = overrideByStat[statName]
		if override ~= nil then
			value = override.value
		end

		resolved[statName] = value
	end

	resolved.MaxHP = math.max(1, resolved.MaxHP)
	resolved.MaxEther = math.max(0, resolved.MaxEther)
	resolved.HPRegenPercent = math.max(0, resolved.HPRegenPercent)
	resolved.DownedHPRegenPercent = math.max(0, resolved.DownedHPRegenPercent)
	resolved.HPRegenFlat = math.max(0, resolved.HPRegenFlat)
	resolved.EtherRegenPercent = math.max(0, resolved.EtherRegenPercent)
	resolved.DownedEtherRegenPercent = math.max(0, resolved.DownedEtherRegenPercent)
	resolved.EtherRegenFlat = math.max(0, resolved.EtherRegenFlat)
	resolved.RegenDelay = math.max(0, resolved.RegenDelay)
	resolved.HPRegenCombatScale = math.max(0, resolved.HPRegenCombatScale)
	resolved.EtherRegenCombatScale = math.max(0, resolved.EtherRegenCombatScale)

	return resolved
end

function StatsService.Init()
	if StatsService._initialized then
		return
	end
	StatsService._initialized = true

	ModifierService.Init()
	ModifierService.BindChanged(function(player)
		invalidatePlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

function StatsService.Invalidate(player: Player)
	invalidatePlayer(player)
end

function StatsService.ResolvePlayerStats(player: Player): ResolvedStats
	local cacheLifetime = math.max(0, tonumber(StatsService.Config.CacheLifetime) or 0)
	local now = os.clock()
	local cachedEntry = cache[player]
	if cacheLifetime > 0 and cachedEntry and now <= cachedEntry.expiresAt then
		return cachedEntry.stats
	end

	local resolved = applyModifiers(player, getBaseStats(player))
	if cacheLifetime > 0 then
		cache[player] = {
			stats = resolved,
			expiresAt = now + cacheLifetime,
		}
	else
		cache[player] = nil
	end
	return resolved
end

function StatsService.RefreshHumanoidMaxHealth(player: Player, humanoid: Humanoid?, resolvedStats: ResolvedStats?): number?
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local resolved = resolvedStats or StatsService.ResolvePlayerStats(player)
	local desiredMax = resolved.MaxHP
	if math.abs(humanoid.MaxHealth - desiredMax) <= 0.001 then
		return desiredMax
	end

	local previousMax = humanoid.MaxHealth
	local healthRatio = (previousMax > 0) and (humanoid.Health / previousMax) or 1

	humanoid.MaxHealth = desiredMax
	humanoid.Health = math.clamp(desiredMax * healthRatio, 0, desiredMax)
	return desiredMax
end

return StatsService
