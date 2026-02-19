local module = {}

function module.FindChildCaseInsensitive(parent: Instance?, targetName: string): Instance?
	if not parent or targetName == "" then
		return nil
	end

	local direct = parent:FindFirstChild(targetName)
	if direct then
		return direct
	end

	local loweredTarget = string.lower(targetName)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == loweredTarget then
			return child
		end
	end

	return nil
end

function module.FindDescendantCaseInsensitive(parent: Instance?, targetName: string): Instance?
	if not parent or targetName == "" then
		return nil
	end

	local loweredTarget = string.lower(targetName)
	for _, descendant in ipairs(parent:GetDescendants()) do
		if string.lower(descendant.Name) == loweredTarget then
			return descendant
		end
	end

	return nil
end

function module.FindByPathCaseInsensitive(root: Instance?, path: { string }): Instance?
	local current = root
	for _, segment in ipairs(path) do
		if not current then
			return nil
		end
		current = module.FindChildCaseInsensitive(current, segment)
	end

	return current
end

function module.AppendUniqueString(target: { string }, seen: { [string]: boolean }, value: any)
	if typeof(value) ~= "string" or value == "" then
		return
	end
	if seen[value] then
		return
	end

	seen[value] = true
	table.insert(target, value)
end

return table.freeze(module)
