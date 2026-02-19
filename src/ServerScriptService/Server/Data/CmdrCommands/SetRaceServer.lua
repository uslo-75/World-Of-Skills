local ServerScriptService = game:GetService("ServerScriptService")
local CmdrAdminUtil = require(ServerScriptService.Server.Data.CmdrAdminUtil)

return function(_context, playersArg, race, varansPath, resetCustomization)
	local players = CmdrAdminUtil.GetPlayers(playersArg)
	local changed = 0
	local failed = {}
	local resetFlag = resetCustomization == true

	for _, player in ipairs(players) do
		local okRace, errRace = CmdrAdminUtil.SetRace(player, race, varansPath, resetFlag)
		if not okRace then
			table.insert(failed, ("%s: %s"):format(CmdrAdminUtil.GetPlayerLabel(player), tostring(errRace)))
			continue
		end

		local okRefresh, errRefresh = CmdrAdminUtil.RefreshCustomization(player)
		if not okRefresh then
			table.insert(
				failed,
				("%s: Race changee mais refresh KO (%s)"):format(
					CmdrAdminUtil.GetPlayerLabel(player),
					tostring(errRefresh)
				)
			)
		end

		changed += 1
	end

	return CmdrAdminUtil.FormatSummary("Race appliquee", changed, #players, failed)
end
