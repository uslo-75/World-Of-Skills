local ServerScriptService = game:GetService("ServerScriptService")
local CmdrAdminUtil = require(ServerScriptService.Server.Data.CmdrAdminUtil)

return function(_context, playersArg, amount)
	local players = CmdrAdminUtil.GetPlayers(playersArg)
	local changed = 0
	local failed = {}

	for _, player in ipairs(players) do
		local ok, err = CmdrAdminUtil.AdjustCurrency(player, "ChronoCrystal", "set", amount)
		if ok then
			changed += 1
		else
			table.insert(failed, ("%s: %s"):format(CmdrAdminUtil.GetPlayerLabel(player), tostring(err)))
		end
	end

	return CmdrAdminUtil.FormatSummary("ChronoCrystal definis", changed, #players, failed)
end
