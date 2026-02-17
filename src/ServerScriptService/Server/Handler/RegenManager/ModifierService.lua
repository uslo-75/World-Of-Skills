local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ModifierService = {}

ModifierService.Config = {
	CleanupInterval = 0.5, -- seconds between expired-modifier sweeps
}

type ModifierMode = "Add" | "Mul" | "Override"
type ModifierEntry = {
	id: string,
	stat: string,
	mode: ModifierMode,
	value: number,
	stacks: number,
	source: string?,
	tags: { [string]: any }?,
	addedAt: number,
	expiresAt: number?,
}

local VALID_MODES = {
	Add = true,
	Mul = true,
	Override = true,
}

local modifiersByPlayer: { [Player]: { [string]: ModifierEntry } } = {}
local changedCallbacks: { [number]: (Player) -> () } = {}
local callbackId = 0
local cleanupConn: RBXScriptConnection? = nil
local cleanupAccumulator = 0

local function getBucket(player: Player): { [string]: ModifierEntry }
	local bucket = modifiersByPlayer[player]
	if not bucket then
		bucket = {}
		modifiersByPlayer[player] = bucket
	end
	return bucket
end

local function copyTags(tags): { [string]: any }?
	if typeof(tags) ~= "table" then
		return nil
	end

	local out = {}
	for k, v in pairs(tags) do
		out[k] = v
	end
	return out
end

local function emitChanged(player: Player)
	for _, callback in pairs(changedCallbacks) do
		local ok, err = pcall(callback, player)
		if not ok then
			warn("[ModifierService] Changed callback failed:", err)
		end
	end
end

local function normalizeModifier(modifierData): (ModifierEntry?, string?)
	if typeof(modifierData) ~= "table" then
		return nil, "modifier must be a table"
	end

	local id = modifierData.id or modifierData.Id
	if typeof(id) ~= "string" or id == "" then
		return nil, "modifier.id is required"
	end

	local stat = modifierData.stat or modifierData.Stat
	if typeof(stat) ~= "string" or stat == "" then
		return nil, "modifier.stat is required"
	end

	local mode = (modifierData.mode or modifierData.Mode or "Add") :: ModifierMode
	if typeof(mode) ~= "string" or not VALID_MODES[mode] then
		return nil, "modifier.mode must be Add, Mul, or Override"
	end

	local value = tonumber(modifierData.value or modifierData.Value)
	if value == nil then
		return nil, "modifier.value must be numeric"
	end

	local stacks = tonumber(modifierData.stacks or modifierData.Stacks) or 1
	stacks = math.max(1, math.floor(stacks))

	local duration = tonumber(modifierData.duration or modifierData.Duration)
	local now = os.clock()
	local expiresAt = nil
	if duration and duration > 0 then
		expiresAt = now + duration
	end

	local source = modifierData.source or modifierData.Source
	if source ~= nil and typeof(source) ~= "string" then
		source = tostring(source)
	end

	return {
		id = id,
		stat = stat,
		mode = mode,
		value = value,
		stacks = stacks,
		source = source,
		tags = copyTags(modifierData.tags or modifierData.Tags),
		addedAt = now,
		expiresAt = expiresAt,
	}
end

local function removeExpiredForPlayer(player: Player): boolean
	local bucket = modifiersByPlayer[player]
	if not bucket then
		return false
	end

	local now = os.clock()
	local changed = false
	for id, entry in pairs(bucket) do
		if entry.expiresAt and now >= entry.expiresAt then
			bucket[id] = nil
			changed = true
		end
	end

	if next(bucket) == nil then
		modifiersByPlayer[player] = nil
	end

	return changed
end

local function cleanupExpired()
	if next(modifiersByPlayer) == nil then
		return
	end

	for player in pairs(modifiersByPlayer) do
		if removeExpiredForPlayer(player) then
			emitChanged(player)
		end
	end
end

function ModifierService.Init()
	if ModifierService._initialized then
		return
	end
	ModifierService._initialized = true

	Players.PlayerRemoving:Connect(function(player)
		modifiersByPlayer[player] = nil
	end)

	cleanupConn = RunService.Heartbeat:Connect(function(dt)
		if next(modifiersByPlayer) == nil then
			cleanupAccumulator = 0
			return
		end

		cleanupAccumulator += dt
		local interval = math.max(0.05, tonumber(ModifierService.Config.CleanupInterval) or 0.5)
		while cleanupAccumulator >= interval do
			cleanupAccumulator -= interval
			cleanupExpired()
		end
	end)
end

function ModifierService.BindChanged(callback: (Player) -> ()): () -> ()
	assert(typeof(callback) == "function", "ModifierService.BindChanged expects a function")

	callbackId += 1
	local id = callbackId
	changedCallbacks[id] = callback

	return function()
		changedCallbacks[id] = nil
	end
end

function ModifierService.AddModifier(player: Player, modifierData): (boolean, string?)
	if not player then
		return false, "player missing"
	end

	local normalized, err = normalizeModifier(modifierData)
	if not normalized then
		return false, err
	end

	local bucket = getBucket(player)
	bucket[normalized.id] = normalized
	emitChanged(player)
	return true, nil
end

function ModifierService.RemoveModifier(player: Player, modifierId: string): boolean
	local bucket = modifiersByPlayer[player]
	if not bucket then
		return false
	end

	if bucket[modifierId] == nil then
		return false
	end

	bucket[modifierId] = nil
	if next(bucket) == nil then
		modifiersByPlayer[player] = nil
	end
	emitChanged(player)
	return true
end

function ModifierService.ClearSource(player: Player, sourceName: string): number
	local bucket = modifiersByPlayer[player]
	if not bucket then
		return 0
	end

	local removed = 0
	for id, entry in pairs(bucket) do
		if entry.source == sourceName then
			bucket[id] = nil
			removed += 1
		end
	end

	if removed > 0 then
		if next(bucket) == nil then
			modifiersByPlayer[player] = nil
		end
		emitChanged(player)
	end

	return removed
end

function ModifierService.ClearAll(player: Player)
	if modifiersByPlayer[player] == nil then
		return
	end
	modifiersByPlayer[player] = nil
	emitChanged(player)
end

function ModifierService.GetModifiers(player: Player, statFilter: string?): { ModifierEntry }
	removeExpiredForPlayer(player)

	local bucket = modifiersByPlayer[player]
	if not bucket then
		return {}
	end

	local out = {}
	for _, entry in pairs(bucket) do
		if statFilter == nil or entry.stat == statFilter then
			table.insert(out, table.clone(entry))
		end
	end

	table.sort(out, function(a, b)
		return a.addedAt < b.addedAt
	end)

	return out
end

function ModifierService.HasModifier(player: Player, modifierId: string): boolean
	removeExpiredForPlayer(player)
	local bucket = modifiersByPlayer[player]
	return bucket ~= nil and bucket[modifierId] ~= nil
end

return ModifierService
