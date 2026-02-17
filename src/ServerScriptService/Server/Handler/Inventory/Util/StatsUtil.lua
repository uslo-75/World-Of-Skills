local StatsUtil = {}

local function statsTableToString(statsTable): string
	if typeof(statsTable) ~= "table" then
		return ""
	end
	local keys = {}
	for k in pairs(statsTable) do
		if typeof(k) == "string" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)

	local parts = {}
	for _, key in ipairs(keys) do
		local v = tonumber(statsTable[key])
		if v ~= nil then
			table.insert(parts, (`%s: %s`):format(key, v))
		end
	end
	return table.concat(parts, ", ")
end

function StatsUtil.Parse(rawStats, dataManager)
	if typeof(rawStats) == "table" then
		local parsed = {}
		for statName, rawValue in pairs(rawStats) do
			if typeof(statName) == "string" then
				local numeric = tonumber(rawValue)
				if numeric ~= nil then
					parsed[statName] = numeric
				end
			end
		end
		return parsed
	end

	if typeof(rawStats) == "string" and dataManager and dataManager.parseStatsString then
		return dataManager.parseStatsString(rawStats)
	end

	return {}
end

function StatsUtil.ToString(stats, dataManager)
	if typeof(stats) == "string" then
		return stats
	end
	return statsTableToString(StatsUtil.Parse(stats, dataManager))
end

return StatsUtil
