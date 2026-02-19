local combatRoot = script:FindFirstAncestor("Combat")
if not combatRoot then
	error(("[CriticalRequestValidator] Combat root not found from %s"):format(script:GetFullName()))
end

local M1RequestValidator =
	require(combatRoot:WaitForChild("M1"):WaitForChild("M1Service"):WaitForChild("M1RequestValidator"))

local module = {}

function module.ValidateRequest(player: Player, payload: any, blockedAttrs: { string })
	if payload ~= nil and typeof(payload) ~= "table" then
		return false, "InvalidPayload"
	end

	local action = payload and payload.action
	if action ~= nil and action ~= "Use" then
		return false, "InvalidAction"
	end

	return M1RequestValidator.ValidateRequest(player, payload, blockedAttrs)
end

return table.freeze(module)
