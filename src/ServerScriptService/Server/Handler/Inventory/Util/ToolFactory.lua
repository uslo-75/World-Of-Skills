local ServerStorage = game:GetService("ServerStorage")

local ToolFactory = {}
ToolFactory.__index = ToolFactory

local function matchesTemplateQuery(tool: Tool, query: string): boolean
	if tool.Name == query then
		return true
	end

	local displayName = tool:GetAttribute("Name")
	if typeof(displayName) == "string" and displayName == query then
		return true
	end

	local weaponName = tool:GetAttribute("Weapon")
	if typeof(weaponName) == "string" and weaponName == query then
		return true
	end

	return false
end

function ToolFactory.new(deps)
	local self = setmetatable({}, ToolFactory)

	self.Config = deps.Config
	self.StatsUtil = deps.StatsUtil
	self.DataManager = deps.DataManager

	self._templateCache = {}
	self._toolsRoot = nil

	return self
end

function ToolFactory:_getToolsRoot()
	if self._toolsRoot and self._toolsRoot.Parent then
		return self._toolsRoot
	end

	local folder = ServerStorage:FindFirstChild(self.Config.ToolsFolderName)
	if folder and folder:IsA("Folder") then
		self._toolsRoot = folder
		return folder
	end

	return nil
end

function ToolFactory:_findTemplate(toolName: string)
	if toolName == "" then
		return nil
	end

	local cached = self._templateCache[toolName]
	if cached and cached.Parent then
		return cached
	end

	local root = self:_getToolsRoot()
	if not root then
		return nil
	end

	-- Primary lookup for weapon tools (respawn/rejoin flow).
	local weaponFolder = root:FindFirstChild("Weapon")
	if weaponFolder and weaponFolder:IsA("Folder") then
		local direct = weaponFolder:FindFirstChild(toolName)
		if direct and direct:IsA("Tool") then
			self._templateCache[toolName] = direct
			return direct
		end

		for _, d in ipairs(weaponFolder:GetDescendants()) do
			if d:IsA("Tool") and matchesTemplateQuery(d, toolName) then
				self._templateCache[toolName] = d
				return d
			end
		end
	end

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Tool") and matchesTemplateQuery(d, toolName) then
			self._templateCache[toolName] = d
			return d
		end
	end

	return nil
end

local function createFallbackTool(itemData)
	local t = Instance.new("Tool")
	t.Name = itemData.name
	t.RequiresHandle = false
	t.CanBeDropped = true
	return t
end

function ToolFactory:ApplyAttributes(tool: Tool, itemData)
	local canonicalName = tool.Name
	local existingDisplayName = tool:GetAttribute("Name")
	local displayName = existingDisplayName
	if typeof(displayName) ~= "string" or displayName == "" then
		displayName = canonicalName
	end
	local statsString = self.StatsUtil.ToString(itemData.statsRaw or itemData.stats, self.DataManager)
	local typeValue = itemData.type
	if typeof(typeValue) ~= "string" or typeValue == "" then
		typeValue = tool:GetAttribute("Type")
	end
	local rarityValue = itemData.rarity
	if typeof(rarityValue) ~= "string" or rarityValue == "" then
		rarityValue = tool:GetAttribute("Rarity")
	end
	local descriptionValue = itemData.description
	if typeof(descriptionValue) ~= "string" or descriptionValue == "" then
		descriptionValue = tool:GetAttribute("Description")
	end

	tool.Name = canonicalName
	tool:SetAttribute("InventoryId", itemData.id)
	tool:SetAttribute("Name", displayName)
	tool:SetAttribute("TemplateName", canonicalName)
	tool:SetAttribute("Stats", statsString)
	tool:SetAttribute("Enchant", itemData.enchant)
	tool:SetAttribute("Type", typeValue)
	tool:SetAttribute("Rarity", rarityValue)
	tool:SetAttribute("Description", descriptionValue)
end

function ToolFactory:CreateToolFromItem(itemData)
	if typeof(itemData) ~= "table" then
		return nil
	end
	if typeof(itemData.name) ~= "string" or itemData.name == "" then
		return nil
	end

	local template = self:_findTemplate(itemData.name)
	local tool = template and template:Clone() or createFallbackTool(itemData)

	if not tool:IsA("Tool") then
		if tool then
			tool:Destroy()
		end
		return nil
	end

	self:ApplyAttributes(tool, itemData)
	return tool
end

function ToolFactory:SerializeTool(tool: Tool)
	return {
		id = tool:GetAttribute("InventoryId"),
		name = tool.Name,
		statsRaw = tool:GetAttribute("Stats"),
		enchant = tool:GetAttribute("Enchant"),
		type = tool:GetAttribute("Type"),
		rarity = tool:GetAttribute("Rarity"),
		description = tool:GetAttribute("Description"),
		createdAt = os.time(),
	}
end

function ToolFactory:ClearCache()
	table.clear(self._templateCache)
end

return ToolFactory
