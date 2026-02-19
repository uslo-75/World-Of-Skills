local ServerScriptService = game:GetService("ServerScriptService")
local CmdrAdminUtil = require(ServerScriptService.Server.Data.CmdrAdminUtil)

return function(_context, playersArg)
	local players = CmdrAdminUtil.GetPlayers(playersArg)
	local changed = 0
	local failed = {}

	for _, player in ipairs(players) do
		local ok, err = CmdrAdminUtil.RefreshCustomization(player)
		if ok then
			changed += 1
		else
			table.insert(failed, ("%s: %s"):format(CmdrAdminUtil.GetPlayerLabel(player), tostring(err)))
		end
	end

	return CmdrAdminUtil.FormatSummary("Customization refresh", changed, #players, failed)
end
