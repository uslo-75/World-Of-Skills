local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InstanceUtil = require(
	ReplicatedStorage:WaitForChild("LocalHandler"):WaitForChild("libs"):WaitForChild("Common"):WaitForChild("InstanceUtil")
)

local criticalVisual = require(script.Parent:WaitForChild("Critical"))

local module = {}

local function findByPath(root: Instance?, path: { string }): Instance?
	local current = root
	for _, name in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function getVfxRoots(): { Instance }
	local roots = {}

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local assetsVfx = assets and assets:FindFirstChild("vfx")
	if assetsVfx then
		table.insert(roots, assetsVfx)
	end

	local legacyMesh = ReplicatedStorage:FindFirstChild("Mesh")
	local legacyVfx = legacyMesh and legacyMesh:FindFirstChild("vfx")
	if legacyVfx then
		table.insert(roots, legacyVfx)
	end

	return roots
end

local function resolveCharacter(params: any): Model?
	if typeof(params) == "Instance" and params:IsA("Model") then
		return params
	end
	if typeof(params) ~= "table" then
		return nil
	end

	local candidate = params.character or params.Character or params.char or params.Char or params[1]
	if typeof(candidate) == "Instance" and candidate:IsA("Model") then
		return candidate
	end

	return nil
end

local function resolveAction(params: any): string
	if typeof(params) ~= "table" then
		return "hit"
	end

	local raw = params.action
	if raw == nil then
		raw = params.Action
	end
	if raw == nil then
		raw = params[2]
	end

	if typeof(raw) ~= "string" then
		return "hit"
	end

	return string.lower(raw)
end

local function attachEffect(template: Instance, rootPart: BasePart, offset: CFrame, effectName: string): Instance?
	local clone = template:Clone()
	clone.Name = effectName

	if clone:IsA("Attachment") then
		clone.CFrame = offset
		clone.Parent = rootPart
		return clone
	end

	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CFrame = rootPart.CFrame * offset
		clone.Parent = rootPart

		local weld = Instance.new("Weld")
		weld.Part0 = rootPart
		weld.Part1 = clone
		weld.C1 = offset
		weld.Parent = rootPart
		InstanceUtil.DestroyAfter(weld, 5)
		return clone
	end

	if clone:IsA("Model") then
		clone.Parent = rootPart
		clone:PivotTo(rootPart.CFrame * offset)
		return clone
	end

	clone.Parent = rootPart
	return clone
end

local function findTemplate(candidates: { string }): Instance?
	for _, vfxRoot in ipairs(getVfxRoots()) do
		local skillRoot = findByPath(vfxRoot, { "skills", "Mele Swing" })
		if not skillRoot then
			continue
		end

		for _, templateName in ipairs(candidates) do
			local template = skillRoot:FindFirstChild(templateName)
			if template then
				return template
			end
		end
	end

	return nil
end

local function playStageVfx(rootPart: BasePart, stage: string): boolean
	local lowerStage = string.lower(stage)
	local templateCandidates = {}
	local offset = CFrame.new()
	local effectName = "MeleAerial"

	if lowerStage == "air" then
		templateCandidates = { "slash", "Slash", "wind", "Wind" }
		offset = CFrame.new(0.063, 0.949, -0.3) * CFrame.Angles(math.rad(-15), 0, 0)
		effectName = "AerialSlash"
	elseif lowerStage == "down" then
		templateCandidates = { "slash", "Slash", "wind", "Wind" }
		offset = CFrame.new(-0.537, 0.949, 1.008)
		effectName = "AerialDownSlash"
	elseif lowerStage == "hit" then
		templateCandidates = { "Coa", "coa", "COA", "slash", "Slash" }
		offset = CFrame.new(1.006, -0.5, 3.008) * CFrame.Angles(math.rad(20), 0, 0)
		effectName = "AerialCoa"
	else
		return false
	end

	local template = findTemplate(templateCandidates)
	if not template then
		return false
	end

	local effect = attachEffect(template, rootPart, offset, effectName)
	if not effect then
		return false
	end

	InstanceUtil.EmitParticles(effect)
	InstanceUtil.DestroyAfter(effect, 5)
	return true
end

module.Aerial = function(params: any)
	local character = resolveCharacter(params)
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local action = "hit"
	action = resolveAction(params)

	if playStageVfx(rootPart, action) then
		return
	end

	-- Fallback if a stage template is missing in assets.
	if action == "hit" and typeof(criticalVisual.Critical) == "function" then
		criticalVisual.Critical(params)
	end
end

return table.freeze(module)
