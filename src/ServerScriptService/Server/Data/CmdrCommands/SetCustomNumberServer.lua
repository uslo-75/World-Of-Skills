local ServerScriptService = game:GetService("ServerScriptService")
local CmdrAdminUtil = require(ServerScriptService.Server.Data.CmdrAdminUtil)

return function(_context, playersArg, field, value, shouldRefresh)
	local players = CmdrAdminUtil.GetPlayers(playersArg)
	local changed = 0
	local failed = {}
	local refresh = shouldRefresh ~= false

	for _, player in ipairs(players) do
		local okSet, errSet = CmdrAdminUtil.SetCustomNumber(player, field, value)
		if not okSet then
			table.insert(
				failed,
				("%s: %s"):format(CmdrAdminUtil.GetPlayerLabel(player), tostring(errSet))
			)
			continue
		end

		if refresh then
			local okRefresh, errRefresh = CmdrAdminUtil.RefreshCustomization(player)
			if not okRefresh then
				table.insert(
					failed,
					("%s: Valeur changee mais refresh KO (%s)"):format(
						CmdrAdminUtil.GetPlayerLabel(player),
						tostring(errRefresh)
					)
				)
			end
		end

		changed += 1
	end

	return CmdrAdminUtil.FormatSummary("Custom index applique", changed, #players, failed)
end
