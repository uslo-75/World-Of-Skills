local module = {}

local function findAnimationByNames(parent: Instance?, candidates: { string }): Animation?
	if not parent then
		return nil
	end

	for _, name in ipairs(candidates) do
		local direct = parent:FindFirstChild(name)
		if direct and direct:IsA("Animation") then
			return direct
		end
	end

	for _, descendant in ipairs(parent:GetDescendants()) do
		if not descendant:IsA("Animation") then
			continue
		end
		for _, name in ipairs(candidates) do
			if string.lower(descendant.Name) == string.lower(name) then
				return descendant
			end
		end
	end

	return nil
end

function module.ResolveSkillAnimation(service, candidates: { string }): Animation?
	local assets = service.AssetsRoot:FindFirstChild("Assets")
	local animationRoot = assets and assets:FindFirstChild("animation")
	if not animationRoot then
		return nil
	end

	local skillFolder = animationRoot:FindFirstChild("skill") or animationRoot:FindFirstChild("Skill")
	return findAnimationByNames(skillFolder, candidates)
end

return table.freeze(module)
