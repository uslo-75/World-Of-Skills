local Players = game:GetService("Players")

local ToolEquipObserve = {}
ToolEquipObserve.__index = ToolEquipObserve

local LOCAL_PLAYER = Players.LocalPlayer

local function disconnect(conn)
	if conn then
		conn:Disconnect()
	end
end

local function isTool(inst)
	return inst and inst:IsA("Tool")
end

function ToolEquipObserve.new()
	local self = setmetatable({}, ToolEquipObserve)

	self._toolConns = {} -- [Tool] = { conns }
	self._backpackConn = nil
	self._characterConn = nil
	self._backpackAddedConn = nil
	self._characterAddedConn = nil

	self._onEquipped = nil
	self._onUnequipped = nil
	self._onCharacter = nil

	return self
end

function ToolEquipObserve:Stop()
	disconnect(self._backpackConn)
	self._backpackConn = nil

	disconnect(self._characterConn)
	self._characterConn = nil

	disconnect(self._backpackAddedConn)
	self._backpackAddedConn = nil

	disconnect(self._characterAddedConn)
	self._characterAddedConn = nil

	for tool in pairs(self._toolConns) do
		self:_unbindTool(tool)
	end
	table.clear(self._toolConns)

	self._onEquipped = nil
	self._onUnequipped = nil
	self._onCharacter = nil
end

function ToolEquipObserve:_isOwnedTool(tool: Tool)
	local backpack = LOCAL_PLAYER:FindFirstChild("Backpack")
	if backpack and tool:IsDescendantOf(backpack) then
		return true
	end
	local char = LOCAL_PLAYER.Character
	if char and tool:IsDescendantOf(char) then
		return true
	end
	return false
end

function ToolEquipObserve:_unbindTool(tool: Tool)
	local conns = self._toolConns[tool]
	if not conns then
		return
	end
	for _, c in ipairs(conns) do
		disconnect(c)
	end
	self._toolConns[tool] = nil
end

function ToolEquipObserve:_bindTool(tool: Tool)
	if self._toolConns[tool] then
		return
	end

	local conns = {}

	table.insert(
		conns,
		tool.Equipped:Connect(function()
			if self._onEquipped then
				self._onEquipped(tool)
			end
		end)
	)

	table.insert(
		conns,
		tool.Unequipped:Connect(function()
			if self._onUnequipped then
				self._onUnequipped(tool)
			end
		end)
	)

	table.insert(
		conns,
		tool.AncestryChanged:Connect(function()
			if not self:_isOwnedTool(tool) then
				self:_unbindTool(tool)
			end
		end)
	)

	self._toolConns[tool] = conns
end

function ToolEquipObserve:_bindToolsIn(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if isTool(child) then
			self:_bindTool(child)
		end
	end
end

function ToolEquipObserve:_bindBackpack(backpack: Backpack)
	disconnect(self._backpackConn)
	self:_bindToolsIn(backpack)

	self._backpackConn = backpack.ChildAdded:Connect(function(child)
		if isTool(child) then
			self:_bindTool(child)
		end
	end)
end

function ToolEquipObserve:_bindCharacter(char: Model)
	disconnect(self._characterConn)
	self:_bindToolsIn(char)

	self._characterConn = char.ChildAdded:Connect(function(child)
		if isTool(child) then
			self:_bindTool(child)
		end
	end)

	if self._onCharacter then
		self._onCharacter(char)
	end

	local already = char:FindFirstChildWhichIsA("Tool")
	if already and self._onEquipped then
		self._onEquipped(already)
	end
end

function ToolEquipObserve:Start(callbacks)
	self:Stop()

	self._onEquipped = callbacks.onEquipped
	self._onUnequipped = callbacks.onUnequipped
	self._onCharacter = callbacks.onCharacter

	local backpack = LOCAL_PLAYER:FindFirstChild("Backpack")
	if backpack and backpack:IsA("Backpack") then
		self:_bindBackpack(backpack)
	end

	self._backpackAddedConn = LOCAL_PLAYER.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			self:_bindBackpack(child)
		end
	end)

	self._characterAddedConn = LOCAL_PLAYER.CharacterAdded:Connect(function(char)
		self:_bindCharacter(char)
	end)

	if LOCAL_PLAYER.Character then
		self:_bindCharacter(LOCAL_PLAYER.Character)
	end
end

return ToolEquipObserve
