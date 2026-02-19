local ResolverUtil = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("ResolverUtil"))
local InstanceUtil = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("InstanceUtil"))
local CharacterUtil = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CharacterUtil"))
local AssetResolver = require(script.Parent:WaitForChild("AssetResolver"))

local module = {}

local function resolveAction(params: any, defaultAction: string): string
	if typeof(params) ~= "table" then
		return defaultAction
	end

	local raw = params.action
	if raw == nil then
		raw = params.Action
	end
	if raw == nil then
		raw = params.stage
	end
	if raw == nil then
		raw = params.Stage
	end
	if raw == nil then
		raw = params[2]
	end

	if typeof(raw) ~= "string" then
		return defaultAction
	end

	local normalized = string.lower(raw)
	if normalized == "" then
		return defaultAction
	end

	return normalized
end

local function resolveOffset(params: any): CFrame?
	if typeof(params) ~= "table" then
		return nil
	end

	local offset = params.offset
	if offset == nil then
		offset = params.Offset
	end
	if offset == nil then
		offset = params.offsetCFrame
	end
	if offset == nil then
		offset = params.OffsetCFrame
	end
	if offset == nil then
		offset = params[3]
	end

	if typeof(offset) == "CFrame" then
		return offset
	end

	return nil
end

local function cloneAndAttach(template: Instance, rootPart: BasePart, offset: CFrame?): Instance?
	local localOffset = offset or CFrame.new()
	local clone = template:Clone()

	if clone:IsA("Attachment") then
		clone.CFrame = localOffset
		clone.Parent = rootPart
		return clone
	end

	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CFrame = rootPart.CFrame * localOffset
		clone.Parent = rootPart

		local weld = Instance.new("Weld")
		weld.Part0 = rootPart
		weld.Part1 = clone
		weld.C1 = localOffset
		weld.Parent = rootPart
		InstanceUtil.DestroyAfter(weld, 6)
		return clone
	end

	if clone:IsA("Model") then
		clone.Parent = rootPart
		clone:PivotTo(rootPart.CFrame * localOffset)
		return clone
	end

	clone.Parent = rootPart
	return clone
end

local function buildCandidateList(action: string, actionCandidates: { [string]: { string } }?): { string }
	local candidates = {}

	if actionCandidates and typeof(actionCandidates[action]) == "table" then
		for _, name in ipairs(actionCandidates[action]) do
			if typeof(name) == "string" and name ~= "" then
				table.insert(candidates, name)
			end
		end
	end

	if #candidates == 0 then
		table.insert(candidates, action)
	end

	return candidates
end

local function findTemplateInSkillRoot(skillRoot: Instance, candidates: { string }): Instance?
	for _, name in ipairs(candidates) do
		local direct = ResolverUtil.FindChildCaseInsensitive(skillRoot, name)
		if direct then
			return direct
		end
	end

	for _, descendant in ipairs(skillRoot:GetDescendants()) do
		for _, name in ipairs(candidates) do
			if string.lower(descendant.Name) == string.lower(name) then
				return descendant
			end
		end
	end

	for _, descendant in ipairs(skillRoot:GetDescendants()) do
		if descendant:IsA("Attachment") or descendant:IsA("BasePart") or descendant:IsA("Model") then
			return descendant
		end
	end

	return nil
end

function module.PlaySkillEffect(
	replicatedStorage: ReplicatedStorage,
	skillName: string,
	params: any,
	options: { [string]: any }?
): (boolean, string, Instance?, Model?)
	local opts = options or {}
	local action = resolveAction(params, string.lower(tostring(opts.defaultAction or "hit")))
	local character = CharacterUtil.ResolveCharacter(params)
	if not character then
		return false, action, nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false, action, nil, character
	end

	local skillRoot = AssetResolver.ResolveSkillRoot(replicatedStorage, skillName)
	if not skillRoot then
		return false, action, nil, character
	end

	local candidates = buildCandidateList(action, opts.actionCandidates)
	local template = findTemplateInSkillRoot(skillRoot, candidates)
	if not template then
		return false, action, nil, character
	end

	local offset = nil
	if typeof(opts.offsets) == "table" then
		offset = opts.offsets[action]
	end
	local payloadOffset = resolveOffset(params)
	if payloadOffset then
		offset = payloadOffset
	end

	local effect = cloneAndAttach(template, rootPart, offset)
	if not effect then
		return false, action, nil, character
	end

	InstanceUtil.EmitParticles(effect)
	InstanceUtil.DestroyAfter(effect, tonumber(opts.lifeTime) or 5)

	return true, action, effect, character
end

return table.freeze(module)
