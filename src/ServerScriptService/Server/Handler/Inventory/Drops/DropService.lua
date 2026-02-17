local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local DropService = {}
DropService.__index = DropService

function DropService.new(deps)
	local self = setmetatable({}, DropService)

	self.Config = deps.Config
	self.ToolFactory = deps.ToolFactory
	self.StatsUtil = deps.StatsUtil
	self.DataManager = deps.DataManager
	self.InventoryService = deps.InventoryService

	self._worldFolder = nil
	self._drops = {} -- [dropId] = { ownerUserId, itemKey, itemData, count, model, root, picking, pickupAt }

	return self
end

function DropService:_ensureWorldFolder()
	if self._worldFolder and self._worldFolder.Parent then
		return self._worldFolder
	end

	local f = Workspace:FindFirstChild(self.Config.DropFolderName)
	if f and not f:IsA("Folder") then
		f:Destroy()
		f = nil
	end

	if not f then
		f = Instance.new("Folder")
		f.Name = self.Config.DropFolderName
		f.Parent = Workspace
	end

	self._worldFolder = f
	return f
end

local function buildItemKey(statsString, itemData)
	return table.concat({
		tostring(itemData.name or ""),
		tostring(statsString or ""),
		tostring(itemData.enchant or ""),
		tostring(itemData.type or ""),
		tostring(itemData.rarity or ""),
		tostring(itemData.description or ""),
	}, "|")
end

local function getToolHalfHeight(tool: Tool?): number
	if not tool then
		return 0.5
	end
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return math.max(0.05, handle.Size.Y * 0.5)
	end
	return 0.5
end

function DropService:_buildDropCFrame(player: Player, tool: Tool?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local forward = hrp.CFrame.LookVector
		local flat = Vector3.new(forward.X, 0, forward.Z)
		if flat.Magnitude < 0.001 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end

		local base = hrp.Position + (flat * self.Config.DropForwardDistance)
		local castFrom = base + Vector3.new(0, self.Config.DropRaycastStartHeight, 0)
		local castDir = Vector3.new(0, -(self.Config.DropRaycastStartHeight + self.Config.DropRaycastDepth), 0)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, self:_ensureWorldFolder() }

		local ray = Workspace:Raycast(castFrom, castDir, params)
		local half = getToolHalfHeight(tool)
		local groundY = ray and ray.Position.Y or base.Y

		local pos = Vector3.new(base.X, groundY + half + self.Config.DropGroundOffset, base.Z)
		return CFrame.lookAt(pos, pos + flat)
	end

	return CFrame.new(0, 5, 0)
end

function DropService:_findStackable(ownerUserId: number, itemKey: string, pos: Vector3)
	local bestId, bestDist = nil, math.huge
	for id, d in pairs(self._drops) do
		if d.ownerUserId == ownerUserId and d.itemKey == itemKey and d.root and d.root.Parent then
			local dist = (d.root.Position - pos).Magnitude
			if dist <= self.Config.DropStackDistance and dist < bestDist then
				bestDist, bestId = dist, id
			end
		end
	end
	return bestId
end

function DropService:_setCount(dropId: string, count: number)
	local d = self._drops[dropId]
	if not d then
		return 0
	end
	local c = math.max(1, math.floor(tonumber(count) or 1))
	d.count = c
	d.model:SetAttribute("StackCount", c)
	d.root:SetAttribute("StackCount", c)
	return c
end

function DropService:_destroy(dropId: string)
	local d = self._drops[dropId]
	if not d then
		return
	end
	self._drops[dropId] = nil
	if d.model and d.model.Parent then
		d.model:Destroy()
	end
end

local function resolvePlayerFromTouchedPart(hit: BasePart?): Player?
	if not hit then
		return nil
	end
	local m = hit:FindFirstAncestorOfClass("Model")
	if not m then
		return nil
	end
	return Players:GetPlayerFromCharacter(m)
end

function DropService:CreateDrop(ownerUserId: number, itemData, dropCFrame: CFrame)
	if typeof(itemData) ~= "table" or typeof(itemData.name) ~= "string" or itemData.name == "" then
		return nil, "InvalidDropItem"
	end

	local statsString = self.StatsUtil.ToString(itemData.statsRaw or itemData.stats, self.DataManager)
	local itemKey = buildItemKey(statsString, itemData)

	local stackId = self:_findStackable(ownerUserId, itemKey, dropCFrame.Position)
	if stackId then
		local d = self._drops[stackId]
		self:_setCount(stackId, d.count + 1)
		return stackId, nil
	end

	local id = HttpService:GenerateGUID(false)
	local model = Instance.new("Model")
	model.Name = ("Drop_%s"):format(itemData.name)
	model:SetAttribute("DropId", id)
	model.Parent = self:_ensureWorldFolder()

	local visual = self.ToolFactory:CreateToolFromItem(itemData)
	local part = nil
	if visual then
		local handle = visual:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			part = handle:Clone()
		end
		visual:Destroy()
	end
	if not part then
		part = Instance.new("Part")
		part.Size = Vector3.new(1.1, 1.1, 1.1)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
	end

	part.Name = "DropRoot"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = dropCFrame
	part.Parent = model
	model.PrimaryPart = part

	CollectionService:AddTag(part, self.Config.DropVisualTag)

	self._drops[id] = {
		ownerUserId = ownerUserId,
		itemKey = itemKey,
		itemData = {
			name = itemData.name,
			statsRaw = statsString,
			enchant = itemData.enchant,
			type = itemData.type,
			rarity = itemData.rarity,
			description = itemData.description,
		},
		count = 1,
		model = model,
		root = part,
		picking = false,
		pickupAt = os.clock() + self.Config.DropPickupDelay,
	}
	self:_setCount(id, 1)

	part.Touched:Connect(function(hitPart)
		local plr = resolvePlayerFromTouchedPart(hitPart)
		if plr then
			self:TryPickup(plr, id)
		end
	end)

	task.delay(self.Config.DropLifetimeSeconds, function()
		if self._drops[id] and self._drops[id].model == model then
			self:_destroy(id)
		end
	end)

	return id, nil
end

function DropService:TryPickup(player: Player, dropId: string)
	local d = self._drops[dropId]
	if not d then
		return false, "DropMissing"
	end
	if d.picking then
		return false, "DropBusy"
	end
	if os.clock() < d.pickupAt then
		return false, "PickupDelay"
	end

	d.picking = true
	local added, err = self.InventoryService:_addDropStackToPlayer(player, d.itemData, d.count)
	if added <= 0 then
		d.picking = false
		return false, err or "PickupFailed"
	end

	if added >= d.count then
		self:_destroy(dropId)
	else
		self:_setCount(dropId, d.count - added)
		d.picking = false
		d.pickupAt = os.clock() + self.Config.DropPickupDelay
	end
	return true, nil
end

function DropService:BuildDropCFrame(player: Player, tool: Tool?)
	return self:_buildDropCFrame(player, tool)
end

return DropService
