local M1Queries = {}

function M1Queries.IsAttackTool(tool: Instance?): boolean
	return tool ~= nil and tool:IsA("Tool") and tool:GetAttribute("Type") == "Attack"
end

function M1Queries.MatchesToolName(tool: Tool, query: string): boolean
	if tool.Name == query then
		return true
	end

	local displayName = tool:GetAttribute("Name")
	if typeof(displayName) == "string" and displayName == query then
		return true
	end

	local alias = tool:GetAttribute("Weapon")
	if typeof(alias) == "string" and alias == query then
		return true
	end

	return false
end

function M1Queries.GetSelectedAttackTool(character: Model): Tool?
	for _, child in ipairs(character:GetChildren()) do
		if M1Queries.IsAttackTool(child) and child:FindFirstChild("EquipedWeapon") ~= nil then
			return child
		end
	end

	return nil
end

function M1Queries.IsCharacterBusy(character: Model, blockedAttrs: { string }): boolean
	for _, attrName in ipairs(blockedAttrs) do
		if character:GetAttribute(attrName) == true then
			return true
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return true
	end

	return false
end

return table.freeze(M1Queries)
