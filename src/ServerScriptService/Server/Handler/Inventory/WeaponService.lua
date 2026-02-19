local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatStateRules =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatStateRules"))

local WeaponService = {}
WeaponService.__index = WeaponService

local FLAG_NAME = "EquipedWeapon"
local RIGHT_ARM_NAME = "Right Arm"
local LEFT_ARM_NAME = "Left Arm"
local RIGHT_GRIP_NAME = "ToolGrip"
local LEFT_GRIP_NAME = "ToolGrip2"

local RIGHT_GRIP_C0_ONE_HAND = CFrame.new(0.012, -0.834, 0)
local RIGHT_GRIP_C1_UNSELECTED_BODY_ATTACH = CFrame.new(0, -0.6, 1.5) * CFrame.Angles(math.rad(90), 0, 0)
local LEFT_VISIBILITY_BASE_ATTR = "LeftWeaponBaseTransparency"

local REF_CONTAINER_PREFIX = "TempWeaponRef_"
local REF_DUMMY_SUFFIX = "ReferenceDummy"

local function disconnectAll(list)
	for _, conn in ipairs(list) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(list)
end

local function isAttackTool(inst: Instance?): boolean
	return inst ~= nil and inst:IsA("Tool") and inst:GetAttribute("Type") == "Attack"
end

local function isEquipToggleBlocked(character: Model?): boolean
	if not character then
		return true
	end
	return CombatStateRules.IsEquipBlocked(character)
end

local function getSelectedSlot(profileData): number
	local slot = tonumber(profileData and profileData.SelectedSlot) or 1
	slot = math.floor(slot)
	if slot < 1 then
		slot = 1
	end
	return slot
end

local function getCharInfo(profile): { [string]: any }?
	if not profile or not profile.Data then
		return nil
	end

	local slot = getSelectedSlot(profile.Data)
	local slotData = profile.Data[slot]
	if typeof(slotData) ~= "table" then
		return nil
	end

	if typeof(slotData.CharInfo) ~= "table" then
		slotData.CharInfo = {}
	end

	return slotData.CharInfo
end

local function iterOwnedTools(player: Player): { Tool }
	local out, seen = {}, {}

	local function collect(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and not seen[child] then
				seen[child] = true
				table.insert(out, child)
			end
		end
	end

	collect(player:FindFirstChild("Backpack"))
	collect(player.Character)

	return out
end

local function isOwnedTool(player: Player, tool: Tool): boolean
	local backpack = player:FindFirstChild("Backpack")
	if backpack and tool:IsDescendantOf(backpack) then
		return true
	end
	local char = player.Character
	if char and tool:IsDescendantOf(char) then
		return true
	end
	return false
end

local function getSelectionFlag(tool: Tool): Folder?
	local flag = tool:FindFirstChild(FLAG_NAME)
	if flag and flag:IsA("Folder") then
		return flag
	end
	return nil
end

local function matchesWeaponName(tool: Tool, queryName: string): boolean
	if tool.Name == queryName then
		return true
	end

	local displayName = tool:GetAttribute("Name")
	if typeof(displayName) == "string" and displayName == queryName then
		return true
	end

	local weaponAlias = tool:GetAttribute("Weapon")
	if typeof(weaponAlias) == "string" and weaponAlias == queryName then
		return true
	end

	return false
end

local function ensureSelectionFlag(tool: Tool): Folder
	local existing = getSelectionFlag(tool)
	if existing then
		return existing
	end
	local flag = Instance.new("Folder")
	flag.Name = FLAG_NAME
	flag.Parent = tool
	return flag
end

local function removeSelectionFlag(tool: Tool)
	local flag = getSelectionFlag(tool)
	if flag then
		flag:Destroy()
	end
end

local function getFirstPartByName(tool: Tool, names: { string }): BasePart?
	for _, name in ipairs(names) do
		local part = tool:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function getAnyPart(tool: Tool): BasePart?
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

local function collectLeftVisualParts(tool: Tool): { BasePart }
	local leftAttach = getFirstPartByName(tool, { "BodyAttach2" })
	if not leftAttach then
		return {}
	end

	local out = {}
	local seen = {}

	local function add(part: BasePart)
		if not seen[part] then
			seen[part] = true
			table.insert(out, part)
		end
	end

	add(leftAttach)

	local function addByLeftNaming()
		add(leftAttach)
		for _, desc in ipairs(tool:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name:match("2$") then
				add(desc)
			end
		end
	end

	local totalParts = 0
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			totalParts += 1
		end
	end

	local connected = {}
	local root = leftAttach:FindFirstAncestorOfClass("WorldModel")
	if root then
		connected = leftAttach:GetConnectedParts(true)
	end
	for _, part in ipairs(connected) do
		if part:IsDescendantOf(tool) then
			add(part)
		end
	end

	-- Fallback naming strategy:
	-- - when not in world (no connected parts found)
	-- - or when connected graph returns almost all parts (single welded assembly)
	if totalParts > 2 and (#out <= 1 or #out >= (totalParts - 1)) then
		table.clear(out)
		table.clear(seen)
		addByLeftNaming()
	end

	return out
end

local function setLeftWeaponVisualHidden(tool: Tool, hidden: boolean)
	local parts = collectLeftVisualParts(tool)
	if #parts == 0 then
		return
	end

	for _, part in ipairs(parts) do
		local baseTransparency = part:GetAttribute(LEFT_VISIBILITY_BASE_ATTR)
		if typeof(baseTransparency) ~= "number" then
			baseTransparency = part.Transparency
			part:SetAttribute(LEFT_VISIBILITY_BASE_ATTR, baseTransparency)
		end

		if hidden then
			part.Transparency = 1
		else
			part.Transparency = baseTransparency
		end
	end
end

local function clearNamedMotor(parent: Instance?, motorName: string)
	if not parent then
		return
	end
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Motor6D") and child.Name == motorName then
			child:Destroy()
		end
	end
end

local function ensureMotor(parent: Instance, motorName: string): Motor6D
	clearNamedMotor(parent, motorName)
	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Parent = parent
	return motor
end

local function normalizeStatsMap(parseStatsString, raw): { [string]: number }
	if typeof(raw) == "table" then
		local map = {}
		for name, value in pairs(raw) do
			local n = tonumber(value)
			if typeof(name) == "string" and n ~= nil then
				map[name] = n
			end
		end
		return map
	end

	if typeof(raw) == "string" and parseStatsString then
		return parseStatsString(raw)
	end

	return {}
end

local function mapsEqual(a: { [string]: number }, b: { [string]: number }): boolean
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in pairs(b) do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

function WeaponService.new(deps)
	local self = setmetatable({}, WeaponService)

	self.DataManager = deps.DataManager

	self._playerConns = {} -- [Player] = {RBXScriptConnection}
	self._toolConns = {} -- [Player] = {[Tool] = {RBXScriptConnection}}

	return self
end

function WeaponService:_clearReferenceVisual(player: Player)
	local char = player.Character
	if not char then
		return
	end

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("WeaponReference") == true then
			child:Destroy()
		end
	end
end

function WeaponService:_getReferenceContainer(player: Player): Model?
	local char = player.Character
	if not char then
		return nil
	end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("WeaponReference") == true then
			return child
		end
	end
	return nil
end

function WeaponService:_applyReferenceTransparency(player: Player, hidden: boolean)
	local container = self:_getReferenceContainer(player)
	if not container then
		return
	end

	for _, desc in ipairs(container:GetDescendants()) do
		if desc:IsA("BasePart") then
			local baseTransparency = desc:GetAttribute("RefBaseTransparency")
			if typeof(baseTransparency) ~= "number" then
				baseTransparency = desc.Transparency
				desc:SetAttribute("RefBaseTransparency", baseTransparency)
			end

			if hidden then
				desc.Transparency = 1
			else
				desc.Transparency = baseTransparency
			end
		end
	end
end

function WeaponService:_findSelectedTool(player: Player): Tool?
	for _, tool in ipairs(iterOwnedTools(player)) do
		if isAttackTool(tool) and getSelectionFlag(tool) then
			return tool
		end
	end
	return nil
end

function WeaponService:_refreshReferenceVisual(player: Player)
	local selectedTool = self:_findSelectedTool(player)
	if not selectedTool then
		self:_clearReferenceVisual(player)
		return
	end

	local container = self:_getReferenceContainer(player)
	local currentWeaponName = container and container:GetAttribute("WeaponName")
	if container == nil or currentWeaponName ~= selectedTool.Name then
		self:_createReferenceVisual(player, selectedTool)
		return
	end

	local char = player.Character
	if char then
		self:_applyReferenceTransparency(player, selectedTool:IsDescendantOf(char))
	end
end

function WeaponService:_createReferenceVisual(player: Player, tool: Tool)
	if not isAttackTool(tool) or not getSelectionFlag(tool) then
		return
	end

	local char = player.Character
	if not char then
		return
	end

	local refsFolder = ServerStorage:FindFirstChild("ReferenceWelds")
	if not refsFolder then
		return
	end

	local reference = refsFolder:FindFirstChild(tool.Name .. REF_DUMMY_SUFFIX) or refsFolder:FindFirstChild(tool.Name)
	if not reference then
		self:_clearReferenceVisual(player)
		return
	end

	self:_clearReferenceVisual(player)

	local container = Instance.new("Model")
	container.Name = REF_CONTAINER_PREFIX .. tool.Name
	container:SetAttribute("WeaponReference", true)
	container:SetAttribute("WeaponName", tool.Name)
	container.Parent = char

	local createdCount = 0
	for _, part in ipairs(reference:GetDescendants()) do
		if part:IsA("BasePart") then
			local weldPartValue = part:FindFirstChild("WeldPart")
			if weldPartValue and weldPartValue:IsA("ObjectValue") and weldPartValue.Value and weldPartValue.Value:IsA("BasePart") then
				local targetName = weldPartValue.Value.Name
				local weldTarget = char:FindFirstChild(targetName, true)
				if weldTarget and weldTarget:IsA("BasePart") then
					local clone = part:Clone()
					clone.Anchored = false
					clone.CanCollide = false
					clone.Massless = true
					clone:SetAttribute("RefBaseTransparency", clone.Transparency)
					clone.CFrame = weldTarget.CFrame * (weldPartValue.Value.CFrame:Inverse() * part.CFrame)
					clone.Parent = container

					local wc = Instance.new("WeldConstraint")
					wc.Part0 = clone
					wc.Part1 = weldTarget
					wc.Parent = clone

					createdCount += 1
				end
			end
		end
	end

	if createdCount == 0 then
		container:Destroy()
		return
	end

	self:_applyReferenceTransparency(player, tool:IsDescendantOf(char))
end

function WeaponService:_applyAttackGrip(player: Player, tool: Tool)
	local char = player.Character
	if not char then
		return
	end
	if tool.Parent ~= char then
		return
	end
	if not isAttackTool(tool) then
		return
	end

	local rightArm = char:FindFirstChild(RIGHT_ARM_NAME)
	local leftArm = char:FindFirstChild(LEFT_ARM_NAME)
	if not rightArm or not rightArm:IsA("BasePart") then
		return
	end

	local rightPart = getFirstPartByName(tool, { "BodyAttach", "Handle", "FalseHandle" }) or getAnyPart(tool)
	if not rightPart then
		return
	end

	local rightGrip = rightArm:FindFirstChild("RightGrip")
	if rightGrip and rightGrip:IsA("Motor6D") then
		rightGrip:Destroy()
	end

	local hasSelectionFlag = getSelectionFlag(tool) ~= nil
	local rightC0 = RIGHT_GRIP_C0_ONE_HAND
	local rightC1 = CFrame.new()
	if rightPart.Name == "BodyAttach" then
		rightC0 = CFrame.new()
		rightC1 = hasSelectionFlag and CFrame.new() or RIGHT_GRIP_C1_UNSELECTED_BODY_ATTACH
	end

	-- Pre-position once before creating the Motor6D to avoid one-frame snap/pop.
	pcall(function()
		rightPart.CFrame = rightArm.CFrame * rightC0 * rightC1:Inverse()
	end)

	local toolGrip = ensureMotor(rightArm, RIGHT_GRIP_NAME)
	toolGrip.Part0 = rightArm
	toolGrip.Part1 = rightPart
	toolGrip.C0 = rightC0
	toolGrip.C1 = rightC1

	if leftArm and leftArm:IsA("BasePart") then
		local leftPart = getFirstPartByName(tool, { "BodyAttach2" })
		if leftPart then
			pcall(function()
				leftPart.CFrame = leftArm.CFrame
			end)

			local toolGrip2 = ensureMotor(leftArm, LEFT_GRIP_NAME)
			toolGrip2.Part0 = leftArm
			toolGrip2.Part1 = leftPart
			toolGrip2.C0 = CFrame.new()
			toolGrip2.C1 = CFrame.new()
		else
			clearNamedMotor(leftArm, LEFT_GRIP_NAME)
		end
	end

	setLeftWeaponVisualHidden(tool, not hasSelectionFlag)
end

function WeaponService:_clearAttackGrip(player: Player)
	local char = player.Character
	if not char then
		return
	end

	local rightArm = char:FindFirstChild(RIGHT_ARM_NAME)
	if rightArm then
		clearNamedMotor(rightArm, RIGHT_GRIP_NAME)
	end

	local leftArm = char:FindFirstChild(LEFT_ARM_NAME)
	if leftArm then
		clearNamedMotor(leftArm, LEFT_GRIP_NAME)
	end
end

function WeaponService:_getWeaponData(player: Player): { [string]: any }?
	local profile = self.DataManager.Profiles[player]
	local charInfo = profile and getCharInfo(profile)
	local weapon = charInfo and charInfo.Weapon
	if typeof(weapon) == "table" and typeof(weapon.name) == "string" and weapon.name ~= "" then
		return weapon
	end
	return nil
end

function WeaponService:_setWeaponDataFromTool(player: Player, tool: Tool)
	local profile = self.DataManager.Profiles[player]
	local charInfo = profile and getCharInfo(profile)
	if not charInfo then
		return false
	end

	local statsRaw = tool:GetAttribute("Stats")
	local parsedStats = normalizeStatsMap(self.DataManager.parseStatsString, statsRaw)
	local stats = (next(parsedStats) ~= nil and parsedStats) or (typeof(statsRaw) == "string" and statsRaw) or nil

	charInfo.Weapon = {
		name = tool.Name,
		stats = stats,
		statsRaw = statsRaw,
		enchant = tool:GetAttribute("Enchant"),
	}

	self.DataManager.RecalculateStats(player)
	return true
end

function WeaponService:_clearWeaponData(player: Player)
	local profile = self.DataManager.Profiles[player]
	local charInfo = profile and getCharInfo(profile)
	if not charInfo then
		return
	end

	if charInfo.Weapon ~= nil then
		charInfo.Weapon = nil
		self.DataManager.RecalculateStats(player)
	end
end

function WeaponService:_toolMatchesWeaponData(tool: Tool, weaponData): boolean
	if not matchesWeaponName(tool, weaponData.name) then
		return false
	end

	local expectedEnchant = weaponData.enchant
	if expectedEnchant ~= nil and tool:GetAttribute("Enchant") ~= expectedEnchant then
		return false
	end

	local expectedStatsRaw = weaponData.statsRaw
	local toolStatsRaw = tool:GetAttribute("Stats")
	if typeof(expectedStatsRaw) == "string" then
		return toolStatsRaw == expectedStatsRaw
	end

	if weaponData.stats ~= nil then
		local a = normalizeStatsMap(self.DataManager.parseStatsString, toolStatsRaw)
		local b = normalizeStatsMap(self.DataManager.parseStatsString, weaponData.stats)
		if not mapsEqual(a, b) then
			return false
		end
	end

	return true
end

function WeaponService:_findBestToolForWeapon(player: Player, weaponData): Tool?
	local fallback = nil

	for _, tool in ipairs(iterOwnedTools(player)) do
		if isAttackTool(tool) and matchesWeaponName(tool, weaponData.name) then
			if not fallback then
				fallback = tool
			end

			if self:_toolMatchesWeaponData(tool, weaponData) then
				return tool
			end
		end
	end

	return fallback
end

function WeaponService:_clearSelectionFlags(player: Player, exceptTool: Tool?)
	for _, tool in ipairs(iterOwnedTools(player)) do
		if isAttackTool(tool) and tool ~= exceptTool then
			removeSelectionFlag(tool)
		end
	end
end

function WeaponService:_restoreSelectionFromProfile(player: Player)
	local weaponData = self:_getWeaponData(player)
	if not weaponData then
		self:_clearSelectionFlags(player, nil)
		self:_clearReferenceVisual(player)
		return
	end

	local selectedTool = self:_findBestToolForWeapon(player, weaponData)
	if not selectedTool then
		self:_clearSelectionFlags(player, nil)
		self:_clearReferenceVisual(player)
		self:_clearWeaponData(player)
		return
	end

	self:_clearSelectionFlags(player, selectedTool)
	ensureSelectionFlag(selectedTool)
	self:_createReferenceVisual(player, selectedTool)
end

function WeaponService:_onToolRemovedFromOwnership(player: Player, tool: Tool)
	if not isAttackTool(tool) then
		return
	end

	local selectedData = self:_getWeaponData(player)
	if not selectedData then
		return
	end

	local wasCurrentWeapon = matchesWeaponName(tool, selectedData.name)
	if not wasCurrentWeapon then
		return
	end

	task.defer(function()
		if player.Parent ~= Players then
			return
		end
		self:_restoreSelectionFromProfile(player)
	end)
end

function WeaponService:_bindTool(player: Player, tool: Tool)
	if not isAttackTool(tool) then
		return
	end

	self._toolConns[player] = self._toolConns[player] or {}
	if self._toolConns[player][tool] then
		return
	end

	local conns = {}
	self._toolConns[player][tool] = conns

	table.insert(
		conns,
		tool.Equipped:Connect(function()
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if char and hum and isEquipToggleBlocked(char) then
				task.defer(function()
					if player.Character ~= char then
						return
					end
					if tool.Parent ~= char then
						return
					end
					hum:UnequipTools()
				end)
				return
			end

			self:_applyAttackGrip(player, tool)
			self:_refreshReferenceVisual(player)
		end)
	)

	table.insert(
		conns,
		tool.Unequipped:Connect(function()
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if char and hum and isEquipToggleBlocked(char) then
				task.defer(function()
					if player.Character ~= char then
						return
					end
					if tool.Parent == char then
						return
					end
					if not isOwnedTool(player, tool) then
						return
					end
					hum:EquipTool(tool)
				end)
				return
			end

			setLeftWeaponVisualHidden(tool, false)
			self:_clearAttackGrip(player)
			self:_refreshReferenceVisual(player)
		end)
	)

	table.insert(
		conns,
		tool.ChildAdded:Connect(function(child)
			if child.Name == FLAG_NAME then
				self:_clearSelectionFlags(player, tool)
				self:_createReferenceVisual(player, tool)
				if player.Character and tool.Parent == player.Character then
					self:_applyAttackGrip(player, tool)
				end
			end
		end)
	)

	table.insert(
		conns,
		tool.ChildRemoved:Connect(function(child)
			if child.Name == FLAG_NAME then
				self:_refreshReferenceVisual(player)
				if player.Character and tool.Parent == player.Character then
					self:_applyAttackGrip(player, tool)
				end
			end
		end)
	)

	table.insert(
		conns,
		tool.AncestryChanged:Connect(function()
			if not isOwnedTool(player, tool) then
				self:_onToolRemovedFromOwnership(player, tool)
				self:_unbindTool(player, tool)
				return
			end

			self:_refreshReferenceVisual(player)
		end)
	)

	local char = player.Character
	if char and tool.Parent == char then
		self:_applyAttackGrip(player, tool)
	end
end

function WeaponService:_unbindTool(player: Player, tool: Tool)
	local byTool = self._toolConns[player]
	if not byTool then
		return
	end
	local conns = byTool[tool]
	if not conns then
		return
	end

	disconnectAll(conns)
	byTool[tool] = nil
end

function WeaponService:_cleanupPlayer(player: Player)
	local conns = self._playerConns[player]
	if conns then
		disconnectAll(conns)
		self._playerConns[player] = nil
	end

	local byTool = self._toolConns[player]
	if byTool then
		for tool, list in pairs(byTool) do
			disconnectAll(list)
			byTool[tool] = nil
		end
		self._toolConns[player] = nil
	end

	self:_clearAttackGrip(player)
	self:_clearReferenceVisual(player)
end

function WeaponService:_bindPlayer(player: Player)
	self:_cleanupPlayer(player)

	local conns = {}
	self._playerConns[player] = conns
	self._toolConns[player] = {}

	local function bindContainer(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				self:_bindTool(player, child)
			end
		end

		table.insert(
			conns,
			container.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					self:_bindTool(player, child)
					self:_refreshReferenceVisual(player)
				end
			end)
		)
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack and backpack:IsA("Backpack") then
		bindContainer(backpack)
	end

	table.insert(
		conns,
		player.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then
				bindContainer(child)
			end
		end)
	)

	local char = player.Character
	if char then
		bindContainer(char)
	end

	table.insert(
		conns,
		player.CharacterAdded:Connect(function(newChar)
			self:_clearAttackGrip(player)
			self:_clearReferenceVisual(player)
			bindContainer(newChar)
			task.defer(function()
				if player.Parent == Players then
					self:_restoreSelectionFromProfile(player)
				end
			end)
		end)
	)
end

function WeaponService:OnInventoryLoaded(player: Player)
	self:_bindPlayer(player)
	self:_restoreSelectionFromProfile(player)
end

function WeaponService:SelectWeapon(player: Player, tool: Tool): (boolean, string?)
	if not isAttackTool(tool) then
		return false, "InvalidToolType"
	end
	if not isOwnedTool(player, tool) then
		return false, "ToolNotOwned"
	end

	local profile = self.DataManager.Profiles[player]
	if not profile then
		return false, "ProfileMissing"
	end

	self:_clearSelectionFlags(player, tool)
	ensureSelectionFlag(tool)

	local ok = self:_setWeaponDataFromTool(player, tool)
	if not ok then
		removeSelectionFlag(tool)
		return false, "WeaponDataUpdateFailed"
	end

	self:_createReferenceVisual(player, tool)
	self:_refreshReferenceVisual(player)

	return true
end

function WeaponService:Init()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_bindPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_bindPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
end

return WeaponService
