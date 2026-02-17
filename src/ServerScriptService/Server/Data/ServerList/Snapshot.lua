local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)

local Snapshot = {}

function Snapshot.resolveGameVersion(config)
	local v = game:GetAttribute("GameVersion")
	if typeof(v) == "string" and v ~= "" then
		return v
	end
	return config.DefaultGameVersion
end

function Snapshot.getActivePlayerIds(activeSet)
	local ids = {}
	for userId in pairs(activeSet) do
		table.insert(ids, userId)
	end
	table.sort(ids)
	return ids
end

function Snapshot.buildServerSnapshot(state, activeSet)
	return {
		serverName = state.serverName,
		serverRegion = state.serverRegionName,
		serverRegionName = state.serverRegionName,
		serverCountry = state.serverCountry,

		serverID = (game.JobId ~= "" and game.JobId) or "Studio",
		placeId = game.PlaceId,

		serverPlayers = #Players:GetPlayers(),
		playerIDs = Snapshot.getActivePlayerIds(activeSet),

		serverAge = Utils.formatServerAge(os.time() - state.serverStartUnix),
		gameVersion = state.gameVersion,
		updatedAt = os.time(),
	}
end

function Snapshot.buildClientPayload(serverSnapshot, progressResolver, player)
	local payload = table.clone(serverSnapshot)

	if progressResolver then
		local ok, name, slot, level = pcall(progressResolver, player)
		if ok then
			payload.playerName = name
			payload.slot = slot
			payload.level = level
			payload.slotText = string.format("Slot-%d [Lv.%d]", slot, level)
		end
	end

	return payload
end

return Snapshot
