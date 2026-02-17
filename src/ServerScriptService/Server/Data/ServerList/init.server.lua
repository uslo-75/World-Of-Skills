local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(script.Config)
local Utils = require(script.Utils)
local RemoteBridge = require(script.RemoteBridge)
local GeoResolver = require(script.GeoResolver)
local Snapshot = require(script.Snapshot)
local MemoryPublisher = require(script.MemoryPublisher)

local serverNames = require(script.ServerNames)

-- OPTIONAL: injecter le progress resolver (comportement actuel conserve)
local DataManager = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Data")
		:WaitForChild("PlayerManager")
		:WaitForChild("DataManager")
)

local function progressResolver(player)
	local playerName = player.DisplayName or player.Name
	local slot = 1
	local level = 1

	local profile = DataManager.Profiles[player]
	local profileData = profile and profile.Data
	if not profileData then
		return playerName, slot, level
	end

	local selectedSlot = tonumber(profileData.SelectedSlot)
	if selectedSlot and selectedSlot >= 1 then
		slot = math.floor(selectedSlot)
	end

	local slotData = profileData[slot]
	local charData = slotData and slotData.CharData
	local power = charData and tonumber(charData.Power)
	if power then
		level = math.max(1, math.floor(power))
	end

	return playerName, slot, level
end

local state = {
	serverName = string.format(
		"%s %s",
		Utils.pickRandom(serverNames.adjectives, "Nameless"),
		Utils.pickRandom(serverNames.objects, "Server")
	),
	serverRegionName = Config.DefaultRegionName,
	serverCountry = "",
	serverRegionResolved = false,
	gameVersion = Snapshot.resolveGameVersion(Config),
	serverStartUnix = os.time(),
}

GeoResolver.applyOverride(state, game:GetAttribute("ServerRegion"))

local activePlayerIds: { [number]: boolean } = {}
local lastRequestAt: { [Player]: number } = {}

local function isLoadedPlayer(player: Player)
	return player.Parent == Players and CollectionService:HasTag(player, "Loaded")
end

local remote = RemoteBridge.ensureRemote(Config.RemotesFolderName, Config.RemoteName)
local publisher = MemoryPublisher.new(Config)

local function buildServerSnapshot()
	return Snapshot.buildServerSnapshot(state, activePlayerIds)
end

local function pushFull(player: Player)
	if not isLoadedPlayer(player) then
		return
	end
	local serverSnapshot = buildServerSnapshot()
	local payload = Snapshot.buildClientPayload(serverSnapshot, progressResolver, player)
	RemoteBridge.push(remote, player, payload)
end

local function pushAgeOnly(ageText: string)
	for _, plr in ipairs(Players:GetPlayers()) do
		if isLoadedPlayer(plr) then
			RemoteBridge.push(remote, plr, { serverAge = ageText })
		end
	end
end

local function waitAndPushWhenLoaded(player: Player)
	task.spawn(function()
		while player.Parent == Players do
			if isLoadedPlayer(player) then
				pushFull(player)
				return
			end
			task.wait(0.25)
		end
	end)
end

local function onPlayerAdded(player: Player)
	activePlayerIds[player.UserId] = true
	waitAndPushWhenLoaded(player)
end

local function onPlayerRemoving(player: Player)
	activePlayerIds[player.UserId] = nil
	lastRequestAt[player] = nil
end

remote.OnServerEvent:Connect(function(player: Player, action)
	if action ~= "request" then
		return
	end

	local now = os.clock()
	local last = lastRequestAt[player]
	if last and (now - last) < Config.RequestCooldown then
		return
	end
	lastRequestAt[player] = now

	pushFull(player)
end)

for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	publisher:remove()
end)

task.spawn(function()
	-- region resolve (best effort) then push refresh
	for _ = 1, Config.GeoLookup.MaxAttempts do
		if GeoResolver.tryResolve(state, Config.GeoLookup) then
			for _, plr in ipairs(Players:GetPlayers()) do
				pushFull(plr)
			end
			break
		end
		task.wait(Config.GeoLookup.RetrySeconds)
	end

	while true do
		local snapshot = buildServerSnapshot()
		publisher:publish(snapshot)
		pushAgeOnly(snapshot.serverAge)
		task.wait(Config.UpdateInterval)
	end
end)
