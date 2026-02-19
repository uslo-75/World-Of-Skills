local M1Queries = require(script.Parent:WaitForChild("M1Queries"))

local module = {}

function module.ValidateRequest(player: Player, payload: any, blockedAttrs: { string })
	if payload ~= nil and typeof(payload) ~= "table" then
		return false, "InvalidPayload"
	end

	local character = player.Character
	if not character or not character.Parent then
		return false, "CharacterMissing"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid then
		return false, "HumanoidMissing"
	end
	if not rootPart then
		return false, "RootMissing"
	end
	if humanoid.Health <= 0 then
		return false, "Dead"
	end

	local equippedTool = M1Queries.GetSelectedAttackTool(character)
	if not equippedTool then
		return false, "NoSelectedAttackTool"
	end

	local payloadToolName = payload and payload.toolName
	if payloadToolName ~= nil then
		if typeof(payloadToolName) ~= "string" then
			return false, "InvalidToolName"
		end
		if not M1Queries.MatchesToolName(equippedTool, payloadToolName) then
			return false, "ToolMismatch"
		end
	end

	if M1Queries.IsCharacterBusy(character, blockedAttrs) then
		return false, "BlockedState"
	end

	return true, {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		equippedTool = equippedTool,
	}
end

return table.freeze(module)
