local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InstanceUtil = require(
	ReplicatedStorage:WaitForChild("LocalHandler"):WaitForChild("libs"):WaitForChild("Common"):WaitForChild("InstanceUtil")
)

local module = {}

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

local function cloneAtRoot(template: Instance, rootPart: BasePart): Instance?
	local clone = template:Clone()

	if clone:IsA("Attachment") then
		clone.Parent = rootPart
		return clone
	end

	if clone:IsA("BasePart") then
		clone.CFrame = rootPart.CFrame
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.Parent = rootPart
		return clone
	end

	if clone:IsA("Model") then
		clone.Parent = rootPart
		clone:PivotTo(rootPart.CFrame)
		return clone
	end

	clone.Parent = rootPart
	return clone
end

local function tryMeleSwing(rootPart: BasePart): boolean
	for _, vfxRoot in ipairs(getVfxRoots()) do
		local template = findByPath(vfxRoot, { "skills", "Mele Swing", "BALAM" })
		if template then
			local effect = cloneAtRoot(template, rootPart)
			if effect then
				InstanceUtil.EmitParticles(effect)
				InstanceUtil.DestroyAfter(effect, 5)
				return true
			end
		end
	end

	return false
end

local function tryHeavySwing(rootPart: BasePart): boolean
	for _, vfxRoot in ipairs(getVfxRoots()) do
		local slashTemplate = findByPath(vfxRoot, { "skills", "Heavy Swing", "DefaultLevel", "Slash" })
		if slashTemplate and slashTemplate:IsA("BasePart") then
			local slash = slashTemplate:Clone()
			slash.Parent = rootPart
			slash.CFrame = rootPart.CFrame
			slash.Anchored = false
			slash.CanCollide = false
			slash.CanTouch = false
			slash.Transparency = 1

			local weld = Instance.new("Weld")
			weld.Part0 = rootPart
			weld.Part1 = slash
			weld.C1 = CFrame.Angles(math.rad(-10.002), math.rad(-90), math.rad(-180))
			weld.Parent = rootPart

			local attachment = slash:FindFirstChild("Attachment")
			if attachment then
				InstanceUtil.EmitParticles(attachment)
			else
				InstanceUtil.EmitParticles(slash)
			end

			InstanceUtil.DestroyAfter(weld, 5)
			InstanceUtil.DestroyAfter(slash, 5)
			return true
		end
	end

	return false
end

module.Critical = function(params: any)
	if resolveAction(params) ~= "hit" then
		return
	end

	local character = resolveCharacter(params)
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	-- Old Mele critical used "Mele Swing". If not found, fallback to "Heavy Swing".
	if tryMeleSwing(rootPart) then
		return
	end

	tryHeavySwing(rootPart)
end

return table.freeze(module)
