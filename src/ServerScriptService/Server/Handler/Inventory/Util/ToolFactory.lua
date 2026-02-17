local ServerStorage = game:GetService("ServerStorage")

local ToolFactory = {}
ToolFactory.__index = ToolFactory

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

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Tool") and d.Name == toolName then
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
	local displayName = itemData.name or tool.Name
	local statsString = self.StatsUtil.ToString(itemData.statsRaw or itemData.stats, self.DataManager)

	tool.Name = displayName
	tool:SetAttribute("InventoryId", itemData.id)
	tool:SetAttribute("Name", displayName)
	tool:SetAttribute("Stats", statsString)
	tool:SetAttribute("Enchant", itemData.enchant)
	tool:SetAttribute("Type", itemData.type)
	tool:SetAttribute("Rarity", itemData.rarity)
	tool:SetAttribute("Description", itemData.description)
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
	local name = tool:GetAttribute("Name")
	if typeof(name) ~= "string" or name == "" then
		name = tool.Name
	end

	return {
		id = tool:GetAttribute("InventoryId"),
		name = name,
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
