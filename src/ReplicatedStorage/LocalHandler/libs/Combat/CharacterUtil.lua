local ResolverUtil = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("ResolverUtil"))

local module = {}

function module.ResolveCharacter(params: any): Model?
	if typeof(params) == "Instance" and params:IsA("Model") then
		return params
	end
	if typeof(params) ~= "table" then
		return nil
	end

	local candidate = params[1] or params.Char or params.Character or params.Target or params.character
	if typeof(candidate) == "Instance" and candidate:IsA("Model") then
		return candidate
	end

	return nil
end

function module.ResolveTool(character: Model): Tool?
	local fallback: Tool? = nil
	for _, child in ipairs(character:GetChildren()) do
		if not child:IsA("Tool") then
			continue
		end

		if child:GetAttribute("Type") == "Attack" and child:FindFirstChild("EquipedWeapon") ~= nil then
			return child
		end

		if not fallback then
			fallback = child
		end
	end

	return fallback
end

function module.FindPartByNames(root: Instance?, names: { string }): BasePart?
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local direct = root:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then
			return direct
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		for _, name in ipairs(names) do
			if descendant.Name == name then
				return descendant
			end
		end
	end

	return nil
end

function module.ResolveSwordPart(character: Model): BasePart?
	local tool = module.ResolveTool(character)
	if not tool then
		return nil
	end

	local partNames = { "Sword", "Blade", "Handle", "BodyAttach" }
	local toolModel = character:FindFirstChild(tool.Name .. "Model")
	local fromModel = module.FindPartByNames(toolModel, partNames)
	if fromModel then
		return fromModel
	end

	return module.FindPartByNames(tool, partNames)
end

function module.CollectWeaponNames(character: Model): { string }
	local names = {}
	local seen = {}

	ResolverUtil.AppendUniqueString(names, seen, character:GetAttribute("Weapon"))

	local tool = module.ResolveTool(character)
	if tool then
		ResolverUtil.AppendUniqueString(names, seen, tool.Name)
		ResolverUtil.AppendUniqueString(names, seen, tool:GetAttribute("Name"))
		ResolverUtil.AppendUniqueString(names, seen, tool:GetAttribute("Weapon"))
	end

	return names
end

return table.freeze(module)
