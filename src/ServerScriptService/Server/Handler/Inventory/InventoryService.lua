local Players = game:GetService("Players")

local InventoryService = {}
InventoryService.__index = InventoryService

function InventoryService.new(deps)
	local self = setmetatable({}, InventoryService)

	self.Config = deps.Config
	self.DataManager = deps.DataManager
	self.ToolFactory = deps.ToolFactory
	self.DropService = deps.DropService
	self.Net = deps.Net

	return self
end

local function ensureFolder(parent: Instance, name: string)
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function ensureNumber(folder: Folder, name: string, defaultValue: number)
	local v = folder:FindFirstChild(name)
	if v and v:IsA("NumberValue") then
		return v
	end
	if v then
		v:Destroy()
	end
	v = Instance.new("NumberValue")
	v.Name = name
	v.Value = defaultValue
	v.Parent = folder
	return v
end

function InventoryService:_updateStats(player: Player)
	local count = self.DataManager.GetInventoryCount(player)
	local cap = self.DataManager.GetInventoryCapacity(player)

	local stats = ensureFolder(player, self.Config.StatsFolderName)
	local attrs = ensureFolder(player, self.Config.AttributesFolderName)

	local a = ensureNumber(stats, self.Config.InventoryCountValueName, count)
	local b = ensureNumber(attrs, self.Config.InventoryCountValueName, count)
	local c = ensureNumber(stats, "MaxCapacity", cap)
	local d = ensureNumber(attrs, "MaxCapacity", cap)

	a.Value = count
	b.Value = count
	c.Value = cap
	d.Value = cap
end

local function iterTools(player: Player, characterOverride: Model?)
	local tools, seen = {}, {}
	local function collect(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and not seen[child] then
				seen[child] = true
				table.insert(tools, child)
			end
		end
	end
	collect(player:FindFirstChild("Backpack"))
	collect(characterOverride or player.Character)
	return tools
end

local function findToolByQuery(player: Player, query: string)
	if query == "" then
		return nil
	end
	for _, tool in ipairs(iterTools(player)) do
		local id = tool:GetAttribute("InventoryId")
		local nm = tool:GetAttribute("Name")
		if id == query or nm == query or tool.Name == query then
			return tool
		end
	end
	return nil
end

function InventoryService:BuildSnapshot(player: Player)
	local items = self.DataManager.GetInventorySnapshot(player)
	local count = self.DataManager.GetInventoryCount(player)
	local cap = self.DataManager.GetInventoryCapacity(player)

	-- Réduction bandwidth : on n’envoie pas des stats tables lourdes, juste statsRaw
	local compact = table.create(math.min(#items, self.Config.MaxItemsInSnapshot))
	for i = 1, math.min(#items, self.Config.MaxItemsInSnapshot) do
		local it = items[i]
		compact[i] = {
			id = it.id,
			name = it.name,
			statsRaw = it.statsRaw or it.stats, -- si stats déjà string, ok
			enchant = it.enchant,
			type = it.type,
			rarity = it.rarity,
			description = it.description,
		}
	end

	local selectedSlot = 1
	local profile = self.DataManager.Profiles[player]
	if profile and profile.Data then
		selectedSlot = math.max(1, math.floor(tonumber(profile.Data.SelectedSlot) or 1))
	end

	return {
		items = compact,
		count = count,
		maxCapacity = cap,
		selectedSlot = selectedSlot,
	}
end

function InventoryService:LoadPlayerInventory(player: Player)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return false, "BackpackMissing"
	end

	local items = self.DataManager.GetInventorySnapshot(player)
	local cap = self.DataManager.GetInventoryCapacity(player)
	if #items > cap then
		local trimmed = table.create(cap)
		for i = 1, cap do
			trimmed[i] = items[i]
		end
		self.DataManager.ReplaceInventory(player, trimmed)
		items = self.DataManager.GetInventorySnapshot(player)
	end

	-- clear live tools
	for _, t in ipairs(iterTools(player)) do
		t:Destroy()
	end

	for _, itemData in ipairs(items) do
		local tool = self.ToolFactory:CreateToolFromItem(itemData)
		if tool then
			tool.Parent = backpack
		end
	end

	self:_updateStats(player)
	self.Net:PushSnapshot(player, "load")
	return true
end

function InventoryService:CapturePlayerInventory(player: Player, characterOverride: Model?, options)
	options = options or {}
	local allowEmptySnapshot = options.allowEmptySnapshot == true

	local liveTools = iterTools(player, characterOverride)
	local serialized = {}
	for _, tool in ipairs(liveTools) do
		table.insert(serialized, self.ToolFactory:SerializeTool(tool))
	end

	-- Protect against data-loss races (void/death teardown):
	-- if live containers are empty but profile still has items, keep profile snapshot.
	if #serialized == 0 and not allowEmptySnapshot then
		local existingCount = self.DataManager.GetInventoryCount(player)
		if existingCount > 0 then
			return true, "SkippedEmptySnapshot"
		end
	end

	local ok = self.DataManager.ReplaceInventory(player, serialized)
	if not ok then
		return false, "ReplaceInventoryFailed"
	end

	local kept = self.DataManager.GetInventoryCount(player)
	if #liveTools > kept then
		for i = kept + 1, #liveTools do
			local overflow = liveTools[i]
			if overflow and overflow.Parent then
				overflow:Destroy()
			end
		end
	end

	self:_updateStats(player)
	self.Net:PushSnapshot(player, "capture")
	return true
end

function InventoryService:_addDropStackToPlayer(player: Player, itemData, amount: number)
	local target = math.max(1, math.floor(tonumber(amount) or 1))
	local added, lastErr = 0, nil
	local addInterval = math.max(0, tonumber(self.Config.BatchAddInterval) or 0)

	for i = 1, target do
		local ok, result = self.DataManager.AddItemToInventory(
			player,
			itemData.name,
			itemData.statsRaw or itemData.stats,
			itemData.enchant,
			{
				type = itemData.type,
				rarity = itemData.rarity,
				description = itemData.description,
				statsRaw = itemData.statsRaw,
			}
		)
		if not ok then
			lastErr = result
			break
		end

		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			local tool = self.ToolFactory:CreateToolFromItem(result)
			if tool then
				tool.Parent = backpack
			end
		end

		added += 1
		if i < target and addInterval > 0 then
			task.wait(addInterval)
		end
	end

	if added > 0 then
		self:_updateStats(player)
		self.Net:PushSnapshot(player, "pickup")
	end

	return added, lastErr
end

local function isEquipBlocked(player: Player): boolean
	local char = player.Character
	if not char then
		return true
	end
	if char:GetAttribute("Downed") == true then
		return true
	end
	if char:GetAttribute("Carrying") == true then
		return true
	end
	if char:GetAttribute("Carried") == true then
		return true
	end
	return false
end

local function normalizedQuery(value): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

local function addQuery(list, seen, value)
	local q = normalizedQuery(value)
	if q and not seen[q] then
		seen[q] = true
		table.insert(list, q)
	end
end

local function buildRemovalQueries(tool: Tool, payload): { string }
	local queries = {}
	local seen = {}

	if typeof(payload) == "table" then
		addQuery(queries, seen, payload.itemId)
		addQuery(queries, seen, payload.itemName)
		addQuery(queries, seen, payload.query)
	end

	addQuery(queries, seen, tool:GetAttribute("InventoryId"))
	addQuery(queries, seen, tool:GetAttribute("Name"))
	addQuery(queries, seen, tool.Name)

	return queries
end

function InventoryService:DropEquippedTool(player: Player, payload)
	if isEquipBlocked(player) then
		return true, "BlockedState"
	end

	local char = player.Character
	if not char then
		return true, "CharacterMissing"
	end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then
		return true, "NoEquippedTool"
	end

	local serialized = self.ToolFactory:SerializeTool(tool)
	local removedItem = serialized
	local removedFromProfile = false

	for _, query in ipairs(buildRemovalQueries(tool, payload)) do
		local okRemove, removed = self.DataManager.RemoveItemFromInventory(player, query, 1)
		if okRemove then
			removedFromProfile = true
			removedItem = (removed and removed[1]) or removedItem
			break
		end
	end

	local dropCFrame = self.DropService:BuildDropCFrame(player, tool)
	local dropId, dropErr = self.DropService:CreateDrop(player.UserId, removedItem, dropCFrame)
	if not dropId then
		if removedFromProfile then
			self.DataManager.AddItemToInventory(
				player,
				removedItem.name,
				removedItem.statsRaw or removedItem.stats,
				removedItem.enchant,
				{
					type = removedItem.type,
					rarity = removedItem.rarity,
					description = removedItem.description,
					statsRaw = removedItem.statsRaw,
				}
			)
			self:_updateStats(player)
			self.Net:PushSnapshot(player, "dropRollback")
		end
		return false, dropErr or "DropCreateFailed"
	end

	tool:Destroy()

	if removedFromProfile then
		self:_updateStats(player)
		self.Net:PushSnapshot(player, "drop")
	else
		local captureOk = self:CapturePlayerInventory(player, nil, { allowEmptySnapshot = true })
		if not captureOk then
			self:_updateStats(player)
			self.Net:PushSnapshot(player, "dropFallback")
		end
	end

	return true, dropId or dropErr
end

function InventoryService:HandleRemoteRequest(player: Player, payload)
	if typeof(payload) ~= "table" then
		return false, "InvalidPayload"
	end
	local action = payload.action
	if typeof(action) ~= "string" then
		return false, "InvalidAction"
	end

	if action == "requestSnapshot" then
		self:_updateStats(player)
		self.Net:PushSnapshot(player, "request", payload.requestId)
		return true
	end

	if action == "equip" then
		if isEquipBlocked(player) then
			return true, "BlockedState"
		end

		local query = tostring(payload.itemId or payload.itemName or "")
		local tool = findToolByQuery(player, query)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if tool and hum then
			hum:EquipTool(tool)
			return true
		end
		return false, "ToolNotFound"
	end

	if action == "unequip" then
		if isEquipBlocked(player) then
			return true, "BlockedState"
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:UnequipTools()
		end
		return true
	end

	if action == "remove" then
		local query = tostring(payload.itemId or payload.itemName or "")
		if query == "" then
			return false, "MissingItemQuery"
		end

		local ok, removed = self.DataManager.RemoveItemFromInventory(player, query, payload.amount)
		if not ok then
			return false, "ItemNotFound"
		end

		for _, rem in ipairs(removed) do
			local q = tostring(rem.id or rem.name or "")
			local t = findToolByQuery(player, q)
			if t then
				t:Destroy()
			end
		end

		self:_updateStats(player)
		self.Net:PushSnapshot(player, "remove")
		return true, removed
	end

	if action == "dropEquipped" then
		return self:DropEquippedTool(player, payload)
	end

	return false, "UnknownAction"
end

function InventoryService:Init()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_updateStats(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_updateStats(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.Net:CleanupPlayer(player)
	end)
end

return InventoryService
