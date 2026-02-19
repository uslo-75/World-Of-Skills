local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local M1Queries =
	require(script.Parent.Parent:WaitForChild("M1"):WaitForChild("M1Service"):WaitForChild("M1Queries"))

local BlockService = {}
BlockService.__index = BlockService

local function toNumber(value: any, defaultValue: number): number
	local parsed = tonumber(value)
	if parsed == nil then
		return defaultValue
	end
	return parsed
end

local function getNumberValue(parent: Instance?, name: string): NumberValue?
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	if child and child:IsA("NumberValue") then
		return child
	end

	return nil
end

local function disconnectAll(connections: { RBXScriptConnection })
	for i = #connections, 1, -1 do
		local conn = connections[i]
		if conn and conn.Connected then
			conn:Disconnect()
		end
		connections[i] = nil
	end
end

function BlockService.new(deps)
	local self = setmetatable({}, BlockService)

	self.Config = deps.Config
	self.StateManager = deps.StateManager

	self._playerConns = {} -- [Player] = RBXScriptConnection
	self._characterConns = {} -- [Player] = { RBXScriptConnection }
	self._parryToken = {} -- [Player] = number
	self._holdingBlock = {} -- [Player] = boolean
	self._nextParryReadyAt = {} -- [Player] = os.clock()
	self._postureDecayConn = nil

	return self
end

function BlockService:_hasSelectedAttackTool(character: Model): boolean
	return M1Queries.GetSelectedAttackTool(character) ~= nil
end

function BlockService:_isBlockedByAttributes(character: Model, attributes: { string }): boolean
	for _, attrName in ipairs(attributes) do
		if character:GetAttribute(attrName) == true then
			return true
		end
	end
	return false
end

function BlockService:_isBlockedByStates(player: Player, states: { string }): boolean
	if not self.StateManager or typeof(self.StateManager.GetState) ~= "function" then
		return false
	end

	for _, stateName in ipairs(states) do
		if self.StateManager.GetState(player, stateName) == true then
			return true
		end
	end

	return false
end

function BlockService:_setDefenseStates(player: Player, character: Model, isBlocking: boolean, isParrying: boolean)
	if character and character.Parent then
		character:SetAttribute("isBlocking", isBlocking)
		character:SetAttribute("Parrying", isParrying)
	end

	if self.StateManager and typeof(self.StateManager.SetState) == "function" then
		self.StateManager.SetState(player, "isBlocking", isBlocking)
		self.StateManager.SetState(player, "Parrying", isParrying)
	end
end

function BlockService:SetDefenseStateForCharacter(character: Model, isBlocking: boolean, isParrying: boolean)
	if not character or not character.Parent then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		self:_setDefenseStates(player, character, isBlocking, isParrying)
		if not isBlocking and not isParrying then
			self._holdingBlock[player] = false
		end
		return
	end

	character:SetAttribute("isBlocking", isBlocking)
	character:SetAttribute("Parrying", isParrying)
end

function BlockService:InterruptDefenseCharacter(character: Model)
	if not character or not character.Parent then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if player then
		self:_stopBlocking(player, character, humanoid)
		return
	end

	character:SetAttribute("isBlocking", false)
	character:SetAttribute("Parrying", false)
	self:_restoreWalkSpeed(character, humanoid)
end

function BlockService:_isRestoreBlocked(character: Model): boolean
	return self:_isBlockedByAttributes(character, self.Config.RestoreBlockedAttrs)
end

function BlockService:_restoreWalkSpeed(character: Model, humanoid: Humanoid?)
	local hum = humanoid
	if not hum or not hum.Parent then
		hum = character:FindFirstChildOfClass("Humanoid")
	end
	if not hum or not hum.Parent then
		return
	end
	if self:_isRestoreBlocked(character) then
		return
	end

	hum.WalkSpeed = math.max(0, toNumber(self.Config.RestoreWalkSpeed, 9))
end

function BlockService:_resolveParryFrame(): number
	return math.max(0.01, toNumber(self.Config.ParryFrame, 0.145))
end

function BlockService:_resolveParryCooldown(parrySucceeded: boolean): number
	local cooldown = parrySucceeded and toNumber(self.Config.ParryHitCooldown, 0.2)
		or toNumber(self.Config.ParryMissCooldown, 1.1)

	return math.max(0, cooldown)
end

function BlockService:_isDefenseCooldownActive(player: Player, character: Model): boolean
	if character:GetAttribute("AutoParryActive") == true then
		return true
	end

	local nextParryReadyAt = self._nextParryReadyAt[player] or 0
	return os.clock() < nextParryReadyAt
end

function BlockService:_resolvePostureValue(player: Player, character: Model): NumberValue?
	local attributesFolder = player:FindFirstChild("Attributes")
	if attributesFolder and attributesFolder:IsA("Folder") then
		local posture = getNumberValue(attributesFolder, "Posture")
		if posture then
			return posture
		end
	end

	local charAttributes = character:FindFirstChild("Attributes")
	if charAttributes and charAttributes:IsA("Folder") then
		return getNumberValue(charAttributes, "Posture")
	end

	return nil
end

function BlockService:_decayPosture(player: Player, deltaTime: number)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	if player:GetAttribute("Combats") == true or character:GetAttribute("Combats") == true then
		return
	end
	if character:GetAttribute("isBlocking") == true or character:GetAttribute("Parrying") == true then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local posture = self:_resolvePostureValue(player, character)
	if not posture or posture.Value <= 0 then
		return
	end

	local decayDelay = math.max(0, toNumber(self.Config.PostureDecayStartDelay, 1.2))
	local lastGainAt = tonumber(character:GetAttribute("PostureLastGainAt")) or 0
	if lastGainAt > 0 and (os.clock() - lastGainAt) < decayDelay then
		return
	end

	local decayPerSecond = math.max(0, toNumber(self.Config.PostureDecayPerSecond, 7))
	if decayPerSecond <= 0 then
		return
	end

	local decayAmount = decayPerSecond * math.max(0, deltaTime)
	if decayAmount <= 0 then
		return
	end

	local nextValue = math.max(0, posture.Value - decayAmount)
	posture.Value = nextValue

	if character:GetAttribute("Posture") ~= nil then
		character:SetAttribute("Posture", nextValue)
	end
end

function BlockService:_stopBlocking(player: Player, character: Model, humanoid: Humanoid?)
	self._parryToken[player] = (self._parryToken[player] or 0) + 1
	self._holdingBlock[player] = false
	self:_setDefenseStates(player, character, false, false)
	self:_restoreWalkSpeed(character, humanoid)
end

function BlockService:_startBlocking(player: Player, character: Model, humanoid: Humanoid): boolean
	if self:_isDefenseCooldownActive(player, character) then
		self._holdingBlock[player] = false
		self:_setDefenseStates(player, character, false, false)
		self:_restoreWalkSpeed(character, humanoid)
		return false
	end

	local token = (self._parryToken[player] or 0) + 1
	self._parryToken[player] = token
	self._holdingBlock[player] = true

	if character:GetAttribute("Running") == true then
		character:SetAttribute("Running", false)
	end
	if self.StateManager and typeof(self.StateManager.SetState) == "function" then
		self.StateManager.SetState(player, "Running", false)
	end

	local parrySuccessSerial = tonumber(character:GetAttribute("ParrySuccessSerial")) or 0

	-- Tap = parry immediately. Holding continues into block once the parry window ends.
	self:_setDefenseStates(player, character, false, true)

	local parryFrame = self:_resolveParryFrame()
	task.delay(parryFrame, function()
		if self._parryToken[player] ~= token then
			return
		end
		if player.Parent ~= Players then
			return
		end
		if character ~= player.Character then
			return
		end
		if not character.Parent then
			return
		end

		local latestParrySerial = tonumber(character:GetAttribute("ParrySuccessSerial")) or 0
		local parrySucceeded = latestParrySerial > parrySuccessSerial
		local cooldown = self:_resolveParryCooldown(parrySucceeded)
		self._nextParryReadyAt[player] = os.clock() + cooldown

		-- Keep hold-to-block smooth: cooldown blocks only future Start requests,
		-- not the same defense hold that just opened the parry window.
		local canStayBlocking = self._holdingBlock[player] == true
		if canStayBlocking then
			self:_setDefenseStates(player, character, true, false)
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = math.max(0, toNumber(self.Config.BlockWalkSpeed, 6))
			end
			return
		end

		self:_setDefenseStates(player, character, false, false)
		self:_restoreWalkSpeed(character, humanoid)
	end)

	return true
end

function BlockService:_disconnectCharacterConns(player: Player)
	local connections = self._characterConns[player]
	if not connections then
		return
	end
	disconnectAll(connections)
	self._characterConns[player] = nil
end

function BlockService:_bindCharacter(player: Player, character: Model)
	self:_disconnectCharacterConns(player)
	self._nextParryReadyAt[player] = 0
	if character:GetAttribute("ParrySuccessSerial") == nil then
		character:SetAttribute("ParrySuccessSerial", 0)
	end
	if character:GetAttribute("AutoParryActive") == nil then
		character:SetAttribute("AutoParryActive", false)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	self:_stopBlocking(player, character, humanoid)

	local connections = {}
	for _, attrName in ipairs(self.Config.InterruptAttrs) do
		table.insert(
			connections,
			character:GetAttributeChangedSignal(attrName):Connect(function()
				if character:GetAttribute(attrName) ~= true then
					return
				end
				if character:GetAttribute("isBlocking") ~= true and character:GetAttribute("Parrying") ~= true then
					return
				end
				self:_stopBlocking(player, character, humanoid)
			end)
		)
	end

	table.insert(
		connections,
		character.ChildRemoved:Connect(function(child)
			if not child:IsA("Tool") then
				return
			end
			if character:GetAttribute("isBlocking") ~= true and character:GetAttribute("Parrying") ~= true then
				return
			end
			if self:_hasSelectedAttackTool(character) then
				return
			end
			self:_stopBlocking(player, character, humanoid)
		end)
	)

	table.insert(
		connections,
		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				self:_disconnectCharacterConns(player)
			end
		end)
	)

	self._characterConns[player] = connections
end

function BlockService:_cleanupPlayer(player: Player)
	self:_disconnectCharacterConns(player)
	self._parryToken[player] = nil
	self._holdingBlock[player] = nil
	self._nextParryReadyAt[player] = nil

	local conn = self._playerConns[player]
	if conn then
		conn:Disconnect()
		self._playerConns[player] = nil
	end
end

function BlockService:Init()
	local function bindPlayer(player: Player)
		local existing = self._playerConns[player]
		if existing then
			existing:Disconnect()
			self._playerConns[player] = nil
		end

		self._playerConns[player] = player.CharacterAdded:Connect(function(character)
			self:_bindCharacter(player, character)
		end)

		if player.Character then
			self:_bindCharacter(player, player.Character)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)

	if self._postureDecayConn then
		self._postureDecayConn:Disconnect()
		self._postureDecayConn = nil
	end

	local interval = math.max(0.05, toNumber(self.Config.PostureDecayInterval, 0.25))
	local elapsed = 0
	self._postureDecayConn = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < interval then
			return
		end

		local step = elapsed
		elapsed = 0
		for _, player in ipairs(Players:GetPlayers()) do
			self:_decayPosture(player, step)
		end
	end)
end

function BlockService:HandleRequest(player: Player, payload: any): (boolean, string?)
	if payload ~= nil and typeof(payload) ~= "table" then
		return false, "InvalidPayload"
	end

	local action = payload and payload.action
	if action ~= "Start" and action ~= "Stop" then
		return false, "InvalidAction"
	end

	local character = player.Character
	if not character or not character.Parent then
		return false, "CharacterMissing"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "HumanoidMissing"
	end
	if humanoid.Health <= 0 then
		return false, "Dead"
	end

	if action == "Stop" then
		self._holdingBlock[player] = false
		if character:GetAttribute("Parrying") == true and character:GetAttribute("isBlocking") ~= true then
			return true
		end
		self:_stopBlocking(player, character, humanoid)
		return true
	end

	if character:GetAttribute("isBlocking") == true then
		return true
	end
	if self:_isDefenseCooldownActive(player, character) then
		return false, "DefenseCooldown"
	end

	if not self:_hasSelectedAttackTool(character) then
		return false, "NoSelectedAttackTool"
	end

	if self:_isBlockedByAttributes(character, self.Config.BlockedStartAttrs) then
		return false, "BlockedState"
	end
	if self:_isBlockedByStates(player, self.Config.BlockedStartStates) then
		return false, "BlockedState"
	end

	local started = self:_startBlocking(player, character, humanoid)
	if not started then
		return false, "DefenseCooldown"
	end

	return true
end

return BlockService
