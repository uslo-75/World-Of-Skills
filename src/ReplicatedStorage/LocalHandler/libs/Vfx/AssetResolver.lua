local ResolverUtil = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("ResolverUtil"))

local module = {}

local cachedVfxFolder: Instance? = nil
local cachedSlowStunnedTemplate: Attachment? = nil

local function resolveVfxFolder(replicatedStorage: ReplicatedStorage): Instance?
	if cachedVfxFolder and cachedVfxFolder.Parent then
		return cachedVfxFolder
	end

	local assets = replicatedStorage:FindFirstChild("Assets")
	local assetsVfx = assets and assets:FindFirstChild("vfx")
	if assetsVfx then
		cachedVfxFolder = assetsVfx
		return cachedVfxFolder
	end

	local legacyMesh = replicatedStorage:FindFirstChild("Mesh")
	local legacyVfx = legacyMesh and legacyMesh:FindFirstChild("vfx")
	if legacyVfx then
		cachedVfxFolder = legacyVfx
		return cachedVfxFolder
	end

	cachedVfxFolder = nil
	return nil
end

function module.GetVfxRoots(replicatedStorage: ReplicatedStorage): { Instance }
	local roots = {}

	local assets = replicatedStorage:FindFirstChild("Assets")
	local assetsVfx = assets and assets:FindFirstChild("vfx")
	if assetsVfx then
		table.insert(roots, assetsVfx)
	end

	local legacyMesh = replicatedStorage:FindFirstChild("Mesh")
	local legacyVfx = legacyMesh and legacyMesh:FindFirstChild("vfx")
	if legacyVfx then
		table.insert(roots, legacyVfx)
	end

	return roots
end

function module.ResolveHitAttachmentTemplate(replicatedStorage: ReplicatedStorage, effectName: string): Attachment?
	local vfxFolder = resolveVfxFolder(replicatedStorage)
	if not vfxFolder then
		return nil
	end

	local effectRoot = ResolverUtil.FindByPathCaseInsensitive(vfxFolder, { "Hitvfx", effectName })
	if not effectRoot then
		return nil
	end

	local direct = ResolverUtil.FindChildCaseInsensitive(effectRoot, "Attachment")
	if direct and direct:IsA("Attachment") then
		return direct
	end

	for _, descendant in ipairs(effectRoot:GetDescendants()) do
		if descendant:IsA("Attachment") then
			return descendant
		end
	end

	return nil
end

function module.ResolveHumanHitTemplate(replicatedStorage: ReplicatedStorage): Instance?
	local vfxFolder = resolveVfxFolder(replicatedStorage)
	if not vfxFolder then
		return nil
	end

	return ResolverUtil.FindByPathCaseInsensitive(vfxFolder, { "Hitvfx", "Hit", "Human" })
end

function module.ResolveDodgeTemplate(replicatedStorage: ReplicatedStorage): Instance?
	local vfxFolder = resolveVfxFolder(replicatedStorage)
	if vfxFolder then
		local dodge = ResolverUtil.FindChildCaseInsensitive(vfxFolder, "Dodge")
		if dodge then
			return dodge
		end
	end

	local legacyMesh = replicatedStorage:FindFirstChild("Mesh")
	local legacyVfx = legacyMesh and legacyMesh:FindFirstChild("vfx")
	if not legacyVfx then
		return nil
	end

	return ResolverUtil.FindChildCaseInsensitive(legacyVfx, "Dodge")
end

function module.ResolveSkillRoot(replicatedStorage: ReplicatedStorage, skillName: string): Instance?
	for _, vfxRoot in ipairs(module.GetVfxRoots(replicatedStorage)) do
		local skillsRoot = ResolverUtil.FindChildCaseInsensitive(vfxRoot, "skills")
		if not skillsRoot then
			continue
		end

		local direct = ResolverUtil.FindChildCaseInsensitive(skillsRoot, skillName)
		if direct then
			return direct
		end

		local deep = ResolverUtil.FindDescendantCaseInsensitive(skillsRoot, skillName)
		if deep then
			return deep
		end
	end

	return nil
end

function module.ResolveSlowStunnedTemplate(replicatedStorage: ReplicatedStorage): Attachment?
	if cachedSlowStunnedTemplate and cachedSlowStunnedTemplate.Parent then
		return cachedSlowStunnedTemplate
	end

	local candidates = {
		"SLOWSTUNNEDPART",
		"SlowStunnedPart",
		"SlowStunned",
	}

	for _, vfxRoot in ipairs(module.GetVfxRoots(replicatedStorage)) do
		for _, candidateName in ipairs(candidates) do
			local root = ResolverUtil.FindDescendantCaseInsensitive(vfxRoot, candidateName)
			if not root then
				continue
			end

			if root:IsA("Attachment") then
				cachedSlowStunnedTemplate = root
				return cachedSlowStunnedTemplate
			end

			local directAttachment = ResolverUtil.FindChildCaseInsensitive(root, "Attachment")
			if directAttachment and directAttachment:IsA("Attachment") then
				cachedSlowStunnedTemplate = directAttachment
				return cachedSlowStunnedTemplate
			end

			local nestedAttachment = root:FindFirstChildWhichIsA("Attachment", true)
			if nestedAttachment then
				cachedSlowStunnedTemplate = nestedAttachment
				return cachedSlowStunnedTemplate
			end
		end
	end

	return nil
end

return table.freeze(module)
