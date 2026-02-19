local CombatWeaponUtil = {}

local function appendUniqueString(target: { string }, seen: { [string]: boolean }, value: any)
	if typeof(value) ~= "string" or value == "" then
		return
	end
	if seen[value] then
		return
	end

	seen[value] = true
	table.insert(target, value)
end

function CombatWeaponUtil.ResolveSelectedOrFirstTool(
	character: Model?,
	getSelectedAttackTool: ((Model) -> Tool?)?
): Tool?
	if not character then
		return nil
	end

	local selected: Tool? = nil
	if typeof(getSelectedAttackTool) == "function" then
		local ok, resolved = pcall(getSelectedAttackTool, character)
		if ok and typeof(resolved) == "Instance" and resolved:IsA("Tool") and resolved.Parent == character then
			selected = resolved
		end
	end
	if selected then
		return selected
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

function CombatWeaponUtil.CollectToolNameCandidates(character: Model?, tool: Tool?): { string }
	local names = {}
	local seen: { [string]: boolean } = {}

	if tool then
		appendUniqueString(names, seen, tool.Name)
		appendUniqueString(names, seen, tool:GetAttribute("Name"))
		appendUniqueString(names, seen, tool:GetAttribute("Weapon"))
	end

	if character then
		appendUniqueString(names, seen, character:GetAttribute("Weapon"))
	end

	return names
end

function CombatWeaponUtil.CollectWeaponSoundNames(
	character: Model?,
	fallbackToolName: string?,
	getSelectedAttackTool: ((Model) -> Tool?)?
): { string }
	local names = {}
	local seen: { [string]: boolean } = {}
	appendUniqueString(names, seen, fallbackToolName)

	if character then
		appendUniqueString(names, seen, character:GetAttribute("Weapon"))

		local tool = CombatWeaponUtil.ResolveSelectedOrFirstTool(character, getSelectedAttackTool)
		if tool then
			appendUniqueString(names, seen, tool.Name)
			appendUniqueString(names, seen, tool:GetAttribute("Name"))
			appendUniqueString(names, seen, tool:GetAttribute("Weapon"))
		end
	end

	return names
end

return table.freeze(CombatWeaponUtil)
