local ResolverUtil = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("ResolverUtil"))
local InstanceUtil = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("InstanceUtil"))
local CharacterUtil = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CharacterUtil"))
local AssetResolver = require(script.Parent:WaitForChild("AssetResolver"))

local module = {}

local function resolvePayloadData(params: any): (Model?, { [string]: any })
	local character = CharacterUtil.ResolveCharacter(params)
	local data = {}

	if typeof(params) ~= "table" then
		return character, data
	end

	local nested = params[2]
	if typeof(nested) == "table" then
		return character, nested
	end

	data.Flags = params.Flags or params.flags
	data.OffsetCFrame = params.OffsetCFrame or params.offset or params.Offset
	data.Action = params.Action or params.action
	return character, data
end

local function normalizeAction(rawAction: any, defaultAction: string): string
	if typeof(rawAction) ~= "string" then
		return defaultAction
	end

	local normalized = string.lower(rawAction)
	if normalized == "enabletrue" then
		return "EnableTrue"
	end
	if normalized == "enablefalse" then
		return "EnableFalse"
	end
	if normalized == "emit" then
		return "Emit"
	end

	return defaultAction
end

local function resolveFlags(data: { [string]: any }, fallbackFlags: { [any]: any }?): { [any]: any }?
	if typeof(data.Flags) == "table" then
		return data.Flags
	end
	if typeof(data.flags) == "table" then
		return data.flags
	end
	if typeof(fallbackFlags) == "table" then
		return fallbackFlags
	end
	return nil
end

local function resolveOffset(data: { [string]: any }, defaultOffset: CFrame?): CFrame
	local offset = data.OffsetCFrame
	if offset == nil then
		offset = data.offset
	end
	if offset == nil then
		offset = data.Offset
	end

	if typeof(offset) == "CFrame" then
		return offset
	end

	if typeof(defaultOffset) == "CFrame" then
		return defaultOffset
	end

	return CFrame.new()
end

local function isFlagEnabled(flags: { [any]: any }?, index: any): boolean
	if typeof(flags) ~= "table" then
		return false
	end
	if flags[index] == true then
		return true
	end
	return flags[tostring(index)] == true
end

local function setEffectEnabled(effect: Instance, enabled: boolean)
	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

local function disableExistingEffect(rootPart: BasePart, effectName: string)
	if typeof(effectName) ~= "string" or effectName == "" then
		return
	end

	for _, child in ipairs(rootPart:GetChildren()) do
		if child.Name == effectName then
			setEffectEnabled(child, false)
		end
	end
end

local function resolveTemplateByName(skillRoot: Instance, templateName: string): Instance?
	local direct = ResolverUtil.FindChildCaseInsensitive(skillRoot, templateName)
	if direct then
		return direct
	end

	for _, descendant in ipairs(skillRoot:GetDescendants()) do
		if string.lower(descendant.Name) == string.lower(templateName) then
			return descendant
		end
	end

	return nil
end

local function attachWeld(rootPart: BasePart, effectPart: BasePart, weldName: string?, offset: CFrame)
	local weld = Instance.new("Weld")
	weld.Name = weldName or "__SkillVfxWeld"
	weld.Part0 = rootPart
	weld.Part1 = effectPart
	weld.C1 = offset
	weld.Parent = effectPart
	InstanceUtil.DestroyAfter(weld, 6)
end

local function attachEffectToRoot(
	rootPart: BasePart,
	template: Instance,
	entry: { [string]: any },
	offset: CFrame
): Instance?
	local clone = template:Clone()
	clone.Name = entry.effect or entry.template or template.Name

	if clone:IsA("Attachment") then
		clone.CFrame = offset
		clone.Parent = rootPart
		return clone
	end

	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CFrame = rootPart.CFrame
		clone.Parent = rootPart
		attachWeld(rootPart, clone, entry.weld, offset)
		return clone
	end

	if clone:IsA("Model") then
		clone.Parent = rootPart
		clone:PivotTo(rootPart.CFrame * offset)

		local primaryPart = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			primaryPart.Anchored = false
			primaryPart.CanCollide = false
			primaryPart.CanTouch = false
			attachWeld(rootPart, primaryPart, entry.weld, offset)
		end

		return clone
	end

	clone.Parent = rootPart
	return clone
end

local function collectTemplateIndexes(templates: { [any]: any }): { any }
	local indexes = {}
	for index, _ in pairs(templates) do
		table.insert(indexes, index)
	end

	table.sort(indexes, function(a, b)
		local na = tonumber(a)
		local nb = tonumber(b)
		if na and nb then
			return na < nb
		end
		return tostring(a) < tostring(b)
	end)

	return indexes
end

function module.PlaySkillTemplates(
	replicatedStorage: ReplicatedStorage,
	skillName: string,
	params: any,
	templates: { [any]: { [string]: any } },
	options: { [string]: any }?
): boolean
	local opts = options or {}
	local character, data = resolvePayloadData(params)
	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local skillRoot = AssetResolver.ResolveSkillRoot(replicatedStorage, skillName)
	if not skillRoot then
		return false
	end

	local flags = resolveFlags(data, opts.defaultFlags)
	local offset = resolveOffset(data, opts.defaultOffset)
	local action = normalizeAction(data.Action or data.action, tostring(opts.defaultAction or "Emit"))
	local lifeTime = tonumber(opts.lifeTime) or 5

	local processed = false
	for _, index in ipairs(collectTemplateIndexes(templates)) do
		if not isFlagEnabled(flags, index) then
			continue
		end

		local entry = templates[index]
		if typeof(entry) ~= "table" then
			continue
		end

		if action == "EnableFalse" then
			disableExistingEffect(rootPart, entry.effect)
			processed = true
			continue
		end

		local templateName = entry.template
		if typeof(templateName) ~= "string" or templateName == "" then
			continue
		end

		local template = resolveTemplateByName(skillRoot, templateName)
		if not template then
			continue
		end

		local effect = attachEffectToRoot(rootPart, template, entry, offset)
		if not effect then
			continue
		end

		if action == "EnableTrue" then
			setEffectEnabled(effect, true)
		else
			InstanceUtil.EmitParticles(effect)
		end

		InstanceUtil.DestroyAfter(effect, lifeTime)
		processed = true
	end

	return processed
end

return table.freeze(module)
