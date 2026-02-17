local Utils = {}

local function getOrCreateWeld(instance)
	local weld = instance:FindFirstChild("Weld")
	if weld and weld:IsA("Weld") then
		return weld
	end

	weld = Instance.new("Weld")
	weld.Name = "Weld"
	weld.Parent = instance

	return weld
end

function Utils.GetOrnamentAsset(root, assetType, index, debugKey)
	if not root then
		warn(("Root introuvable pour ornament (%s)."):format(tostring(debugKey)))
		return nil
	end

	local folder = root:FindFirstChild(assetType)
	if not folder then
		warn(("Pas de dossier '%s' pour %s."):format(assetType, tostring(debugKey)))
		return nil
	end

	local assetName = assetType .. tostring(index)
	local asset = folder:FindFirstChild(assetName)
	if not asset then
		warn(("Pas d'asset '%s' pour %s."):format(assetName, tostring(debugKey)))
		return nil
	end

	return asset
end

function Utils.GetAttachPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		local rootPart = instance:FindFirstChild("RootPart")
		if rootPart and rootPart:IsA("BasePart") then
			return rootPart
		end

		if instance.PrimaryPart and instance.PrimaryPart:IsA("BasePart") then
			return instance.PrimaryPart
		end

		return instance:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

function Utils.CreateWeld(instance, part0)
	local part1 = Utils.GetAttachPart(instance)
	if not part1 then
		return nil
	end

	local weld = getOrCreateWeld(instance)
	weld.Part0 = part0
	weld.Part1 = part1
	return weld
end

function Utils.StartSpin(instance, weld)
	task.spawn(function()
		local angle = 0
		while instance.Parent and weld.Parent do
			angle = (angle + 5) % 360
			weld.C1 = CFrame.Angles(0, math.rad(angle), 0)
			task.wait(0.06)
		end
	end)
end

local function toOrderIndex(orderValue)
	local valueType = typeof(orderValue)
	local n = nil

	if valueType == "number" then
		n = math.floor(orderValue)
	elseif valueType == "string" then
		n = tonumber(orderValue)
		if n then
			n = math.floor(n)
		end
	end

	if not n or n < 1 then
		return nil
	end

	return n
end

local function getOrderKeyFromPart(part)
	-- Expected setup: Attribute named "Order" with value 1, 2, 3...
	local orderIndex = toOrderIndex(part:GetAttribute("Order"))
	if orderIndex then
		return "Order" .. tostring(orderIndex)
	end

	-- Safety fallback if Order was stored as IntValue/NumberValue child.
	local orderValueObject = part:FindFirstChild("Order")
	if orderValueObject and (orderValueObject:IsA("IntValue") or orderValueObject:IsA("NumberValue")) then
		orderIndex = toOrderIndex(orderValueObject.Value)
		if orderIndex then
			return "Order" .. tostring(orderIndex)
		end
	end

	return nil
end

local function toColor3(savedColor)
	if typeof(savedColor) == "Color3" then
		return savedColor
	end

	if type(savedColor) ~= "table" then
		return nil
	end

	local r = tonumber(savedColor.r)
	local g = tonumber(savedColor.g)
	local b = tonumber(savedColor.b)
	if not r or not g or not b then
		return nil
	end

	return Color3.new(r, g, b)
end

function Utils.ApplyOrnamentColors(instance, ornamentColors)
	if type(ornamentColors) ~= "table" then
		return
	end

	local function applyColor(basePart)
		local orderKey = getOrderKeyFromPart(basePart)
		if not orderKey then
			return
		end

		local color3 = toColor3(ornamentColors[orderKey])
		if color3 then
			basePart.Color = color3
		end
	end

	if instance:IsA("BasePart") then
		applyColor(instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			applyColor(descendant)
		end
	end
end

return Utils
