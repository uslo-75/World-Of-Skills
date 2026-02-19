local ServerScriptService = game:GetService("ServerScriptService")
local CmdrAdminUtil = require(ServerScriptService.Server.Data.CmdrAdminUtil)

return function(_context, playersArg, assetId)
	local players = CmdrAdminUtil.GetPlayers(playersArg)
	local changed = 0
	local failed = {}

	for _, player in ipairs(players) do
		local okSet, errSet = CmdrAdminUtil.SetClothing(player, "Pant", assetId)
		if not okSet then
			table.insert(failed, ("%s: %s"):format(CmdrAdminUtil.GetPlayerLabel(player), tostring(errSet)))
			continue
		end

		local okRefresh, errRefresh = CmdrAdminUtil.RefreshCustomization(player)
		if not okRefresh then
			table.insert(
				failed,
				("%s: Pant change mais refresh KO (%s)"):format(
					CmdrAdminUtil.GetPlayerLabel(player),
					tostring(errRefresh)
				)
			)
		end

		changed += 1
	end

	return CmdrAdminUtil.FormatSummary("Pant applique", changed, #players, failed)
end
