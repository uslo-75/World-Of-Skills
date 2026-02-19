local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local M1Constants = require(script:WaitForChild("M1Constants"))
local M1Calc = require(script:WaitForChild("M1Calc"))
local M1Queries = require(script:WaitForChild("M1Queries"))
local M1Anims = require(script:WaitForChild("M1Anims"))
local M1CombatHandler = require(script:WaitForChild("M1CombatHandler"))
local M1RequestValidator = require(script:WaitForChild("M1RequestValidator"))
local CombatWeaponUtil = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("CombatWeaponUtil"))

local ATTR = M1Constants.Attributes
local BLOCKED_SELF_ATTRS = M1Constants.BlockedSelfAttrs

local M1Service = {}
M1Service.__index = M1Service

local function addTrailUnique(target: { Trail }, seen: { [Trail]: boolean }, trail: Trail)
	if seen[trail] then
		return
	end
	seen[trail] = true
	table.insert(target, trail)
end

local function addAnimationUnique(target: { Animation }, seen: { [Animation]: boolean }, animation: Animation?)
	if not animation then
		return
	end
	if seen[animation] then
		return
	end
	seen[animation] = true
	table.insert(target, animation)
end

local TRAIL_START_KEYFRAMES = {
	trailstart = true,
	trail_start = true,
	starttrail = true,
	trailon = true,
	trail_on = true,
}

local TRAIL_END_KEYFRAMES = {
	trailend = true,
	trail_end = true,
	endtrail = true,
	trailoff = true,
	trail_off = true,
}

local SWORD_TIP_KEYFRAMES = {
	swordtip = true,
	sword_tip = true,
	tip = true,
	burst = true,
	crescets = true,
}

local AIRBORNE_STATES = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Flying] = true,
}

local SPECIAL_FALLBACK_REASONS = {
	Cooldown = true,
	WeaponModuleMissing = true,
	NotImplemented = true,
	InvalidWeaponHandler = true,
	InvalidWeaponHandlerResult = true,
	WeaponSpecialUnsupported = true,
}

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

function M1Service.new(deps)
	local self = setmetatable({}, M1Service)

	self.Config = deps.Config
	self.AnimUtil = deps.AnimUtil
	self.SoundUtil = deps.SoundUtil
	self.Replication = deps.Replication
	self.StateManager = deps.StateManager
	self.AssetsRoot = deps.AssetsRoot or ReplicatedStorage
	self.WeaponInfo = deps.WeaponInfo
	self.HitboxModule = deps.HitboxModule
	self.CombatReplication = deps.CombatReplication
	self.DefenseService = deps.DefenseService
	self.HyperArmorService = deps.HyperArmorService
	self.WeaponSpecialService = deps.WeaponSpecialService

	self._hitService = nil
	self._hitServiceFailed = false
	self._lastSwingAt = {} -- [Player] = os.clock()
	self._lastComboAt = {} -- [Player] = os.clock()
	self._comboResetToken = {} -- [Player] = number
	self._combatTagToken = {} -- [Player] = number
	self._activeAttackToken = {} -- [Player] = number
	self._activeWeaponTrails = {} -- [Player] = { token = number, trails = { Trail } }
	self._activeSwordTip = {} -- [Player] = { token = number, instance = Instance, emitters = { ParticleEmitter } }
	self._swordTipTemplate = nil
	self._swordTipTemplateResolved = false
	self._swingTokenByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = number
	self._playerConns = {} -- [Player] = RBXScriptConnection
	self._characterConns = {} -- [Player] = { RBXScriptConnection }
	self._prewarmedToolByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = { [string] = true }

	self._combatHandler = M1CombatHandler.new({
		Config = self.Config,
		AnimUtil = self.AnimUtil,
		AssetsRoot = self.AssetsRoot,
		Replication = self.Replication,
		StateManager = self.StateManager,
		HitboxModule = self.HitboxModule,
		GetHitService = function()
			return self:_getHitService()
		end,
		MarkInCombat = function(player, character)
			self:_markInCombat(player, character)
		end,
		PlayToolSound = function(sourceCharacter, fallbackToolName, soundNames, parent)
			self:_playToolSound(sourceCharacter, fallbackToolName, soundNames, parent)
		end,
		CombatReplication = self.CombatReplication,
		DefenseService = self.DefenseService,
		HyperArmorService = self.HyperArmorService,
	})

	return self
end

function M1Service:_getHitService()
	if self._hitService then
		return self._hitService
	end
	if self._hitServiceFailed then
		return nil
	end

	local modulesFolder = ServerStorage:FindFirstChild("Module")
	local hitServiceModule = modulesFolder and modulesFolder:FindFirstChild("HitService")
	if not hitServiceModule or not hitServiceModule:IsA("ModuleScript") then
		self._hitServiceFailed = true
		return nil
	end

	local ok, result = pcall(require, hitServiceModule)
	if not ok then
		self._hitServiceFailed = true
		warn(("[M1Service] Failed to load HitService: %s"):format(tostring(result)))
		return nil
	end

	self._hitService = result
	return self._hitService
end

function M1Service:_getWeaponStats(toolName: string): { [string]: any }
	if not self.WeaponInfo or typeof(self.WeaponInfo.getWeapon) ~= "function" then
		return {}
	end

	local ok, result = pcall(function()
		return self.WeaponInfo:getWeapon(toolName)
	end)

	if ok and typeof(result) == "table" then
		return result
	end

	return {}
end

function M1Service:_resolveWeaponSoundNames(character: Model?, fallbackToolName: string?): { string }
	return CombatWeaponUtil.CollectWeaponSoundNames(character, fallbackToolName, M1Queries.GetSelectedAttackTool)
end

function M1Service:_playToolSound(
	sourceCharacter: Model?,
	fallbackToolName: string?,
	soundNames: any,
	parent: Instance?
)
	if self.Config.EnableCombatSfx == false then
		return
	end
	if not self.SoundUtil or typeof(self.SoundUtil.PlayTool) ~= "function" then
		return
	end

	local weaponNames = self:_resolveWeaponSoundNames(sourceCharacter, fallbackToolName)
	if #weaponNames == 0 then
		return
	end

	self.SoundUtil.PlayTool(self.AssetsRoot, weaponNames, soundNames, parent)
end

function M1Service:_collectToolNameCandidates(character: Model, tool: Tool): { string }
	return CombatWeaponUtil.CollectToolNameCandidates(character, tool)
end

function M1Service:_collectPrewarmAnimationsForTool(character: Model, tool: Tool): { Animation }
	local animations = {}
	local seen: { [Animation]: boolean } = {}
	local maxCombo = math.max(1, math.floor(M1Calc.ToNumber(self.Config.MaxCombo, 4)))

	for _, toolName in ipairs(self:_collectToolNameCandidates(character, tool)) do
		for combo = 1, maxCombo do
			addAnimationUnique(animations, seen, M1Anims.ResolveSwingAnimation(self.AssetsRoot, toolName, combo))
		end

		addAnimationUnique(animations, seen, M1Anims.ResolveCriticalAnimation(self.AssetsRoot, toolName))
		addAnimationUnique(animations, seen, M1Anims.ResolveWeaponAttackAnimation(self.AssetsRoot, toolName, "Running"))
		addAnimationUnique(animations, seen, M1Anims.ResolveWeaponAttackAnimation(self.AssetsRoot, toolName, "Aerial"))
	end

	return animations
end

function M1Service:_prewarmAttackAnimations(character: Model, tool: Tool)
	if not character or not character.Parent then
		return
	end
	if not tool or not tool.Parent then
		return
	end
	if not M1Queries.IsAttackTool(tool) then
		return
	end
	if not self.AnimUtil or typeof(self.AnimUtil.LoadTrack) ~= "function" then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local cacheByToolName = self._prewarmedToolByCharacter[character]
	if not cacheByToolName then
		cacheByToolName = {}
		self._prewarmedToolByCharacter[character] = cacheByToolName
	end

	local toolNames = self:_collectToolNameCandidates(character, tool)
	local shouldPrewarm = false
	for _, toolName in ipairs(toolNames) do
		if not cacheByToolName[toolName] then
			shouldPrewarm = true
			break
		end
	end
	if not shouldPrewarm then
		return
	end

	for _, animation in ipairs(self:_collectPrewarmAnimationsForTool(character, tool)) do
		local ok, track = pcall(self.AnimUtil.LoadTrack, humanoid, animation, "__Prewarm")
		if ok and track then
			pcall(function()
				track:Stop(0)
			end)
			pcall(function()
				track:Destroy()
			end)
		end
	end

	for _, toolName in ipairs(toolNames) do
		cacheByToolName[toolName] = true
	end
end

function M1Service:_disconnectCharacterConns(player: Player)
	local conns = self._characterConns[player]
	if not conns then
		return
	end

	for i = #conns, 1, -1 do
		local conn = conns[i]
		if conn and conn.Connected then
			conn:Disconnect()
		end
		conns[i] = nil
	end

	self._characterConns[player] = nil
end

function M1Service:_bindCharacterPrewarm(player: Player, character: Model)
	self:_disconnectCharacterConns(player)
	local conns: { RBXScriptConnection } = {}
	self._characterConns[player] = conns

	local function scheduleSelectedPrewarm()
		task.defer(function()
			if player.Character ~= character then
				return
			end
			if not character.Parent then
				return
			end

			local selected = M1Queries.GetSelectedAttackTool(character)
			if selected then
				self:_prewarmAttackAnimations(character, selected)
			end
		end)
	end

	local function tryPrewarmFromInstance(inst: Instance)
		local tool: Tool? = nil
		if inst:IsA("Tool") then
			tool = inst
		else
			tool = inst:FindFirstAncestorOfClass("Tool")
		end

		if not tool or tool.Parent ~= character then
			return
		end

		self:_prewarmAttackAnimations(character, tool)
	end

	table.insert(
		conns,
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				tryPrewarmFromInstance(child)
				scheduleSelectedPrewarm()
			end
		end)
	)

	table.insert(
		conns,
		character.DescendantAdded:Connect(function(inst)
			if inst.Name == "EquipedWeapon" then
				tryPrewarmFromInstance(inst)
				scheduleSelectedPrewarm()
			end
		end)
	)

	table.insert(conns, character:GetAttributeChangedSignal("Weapon"):Connect(scheduleSelectedPrewarm))

	scheduleSelectedPrewarm()
end

function M1Service:_collectWeaponTrails(character: Model, tool: Tool): { Trail }
	local trails = {}
	local seen: { [Trail]: boolean } = {}

	local function collectIn(root: Instance?)
		if not root then
			return
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("Trail") then
				addTrailUnique(trails, seen, descendant)
			end
		end
	end

	collectIn(tool)
	collectIn(character:FindFirstChild(tool.Name .. "Model"))

	if #trails == 0 then
		local function tryAutoTrail(part: BasePart?)
			if not part or not part:IsA("BasePart") then
				return
			end

			local existingTrail = part:FindFirstChild("Trail")
			if existingTrail and existingTrail:IsA("Trail") then
				addTrailUnique(trails, seen, existingTrail)
				return
			end

			local attachments = {}
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("Attachment") then
					table.insert(attachments, child)
				end
			end
			if #attachments < 2 then
				return
			end

			local attachment0 = part:FindFirstChild("Attachment1")
				or part:FindFirstChild("Attachment0")
				or part:FindFirstChild("TrailAttachment0")
				or attachments[1]
			local attachment1 = part:FindFirstChild("Attachment2")
				or part:FindFirstChild("TrailAttachment1")
				or attachments[#attachments]
			if attachment0 == attachment1 then
				return
			end
			if not attachment0 or not attachment1 then
				return
			end
			if not attachment0:IsA("Attachment") or not attachment1:IsA("Attachment") then
				return
			end

			local autoTrail = Instance.new("Trail")
			autoTrail.Name = "__M1AutoTrail"
			autoTrail.Attachment0 = attachment0
			autoTrail.Attachment1 = attachment1
			autoTrail.Lifetime = 0.12
			autoTrail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			autoTrail.Enabled = false
			autoTrail.Parent = part
			addTrailUnique(trails, seen, autoTrail)
		end

		local roots = {
			tool,
			character:FindFirstChild(tool.Name .. "Model"),
		}
		for _, root in ipairs(roots) do
			if not root then
				continue
			end

			tryAutoTrail(root:FindFirstChild("BodyAttach", true))
			tryAutoTrail(root:FindFirstChild("BodyAttach2", true))
		end
	end

	return trails
end

function M1Service:_setWeaponTrailsEnabled(player: Player, token: number, enabled: boolean): boolean
	local activeTrails = self._activeWeaponTrails[player]
	if not activeTrails or activeTrails.token ~= token then
		return false
	end

	local changed = false
	for _, trail in ipairs(activeTrails.trails) do
		if trail and trail.Parent then
			trail.Enabled = enabled
			changed = true
		end
	end

	return changed
end

function M1Service:_resolveSwordTipTemplate(): Instance?
	local cached = self._swordTipTemplate
	if cached and cached.Parent then
		return cached
	end
	if self._swordTipTemplateResolved then
		return nil
	end

	local template = findByPath(self.AssetsRoot, { "Assets", "vfx", "swordTip", "Burst", "Crescets" })
	if not template then
		template = findByPath(self.AssetsRoot, { "Mesh", "vfx", "swordTip", "Burst", "Crescets" })
	end

	if not template then
		local roots = {}
		local assets = self.AssetsRoot:FindFirstChild("Assets")
		if assets then
			table.insert(roots, assets)
		end
		local mesh = self.AssetsRoot:FindFirstChild("Mesh")
		if mesh then
			table.insert(roots, mesh)
		end

		for _, root in ipairs(roots) do
			for _, descendant in ipairs(root:GetDescendants()) do
				if string.lower(descendant.Name) == "crescets" then
					template = descendant
					break
				end
			end
			if template then
				break
			end
		end
	end

	self._swordTipTemplate = template
	self._swordTipTemplateResolved = true
	return template
end

function M1Service:_resolveSwordTipAttachment(character: Model, tool: Tool): Attachment?
	local roots = {
		tool,
		character:FindFirstChild(tool.Name .. "Model"),
	}

	for _, root in ipairs(roots) do
		if not root then
			continue
		end

		for _, name in ipairs({ "Attachment2", "SwordTipAttachment", "SwordTip", "TipAttachment", "Tip" }) do
			local candidate = root:FindFirstChild(name, true)
			if candidate and candidate:IsA("Attachment") then
				return candidate
			end
		end
	end

	for _, root in ipairs(roots) do
		if not root then
			continue
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("Trail") then
				if descendant.Attachment1 then
					return descendant.Attachment1
				end
				if descendant.Attachment0 then
					return descendant.Attachment0
				end
			end
		end
	end

	for _, root in ipairs(roots) do
		if not root then
			continue
		end

		local rightPart = root:FindFirstChild("BodyAttach", true)
			or root:FindFirstChild("Handle", true)
			or root:FindFirstChild("FalseHandle", true)
			or root:FindFirstChild("Sword", true)
			or root:FindFirstChild("Blade", true)

		if rightPart and rightPart:IsA("BasePart") then
			local attach = rightPart:FindFirstChildWhichIsA("Attachment")
			if attach then
				return attach
			end
		end
	end

	return nil
end

function M1Service:_clearSwordTip(player: Player, token: number?, destroyDelay: number?)
	local state = self._activeSwordTip[player]
	if not state then
		return
	end
	if token ~= nil and state.token ~= token then
		return
	end

	local inst = state.instance
	local delaySeconds = math.max(0, tonumber(destroyDelay) or 0)
	if inst and inst.Parent then
		if delaySeconds > 0 then
			task.delay(delaySeconds, function()
				if inst and inst.Parent then
					inst:Destroy()
				end
			end)
		else
			inst:Destroy()
		end
	end

	self._activeSwordTip[player] = nil
end

function M1Service:_spawnSwordTip(player: Player, character: Model, tool: Tool, token: number): boolean
	self:_clearSwordTip(player)

	local template = self:_resolveSwordTipTemplate()
	if not template then
		return false
	end

	local targetAttachment = self:_resolveSwordTipAttachment(character, tool)
	if not targetAttachment then
		return false
	end

	local clone = template:Clone()
	local emitters = {}

	if clone:IsA("ParticleEmitter") or clone:IsA("Beam") or clone:IsA("Trail") then
		clone.Parent = targetAttachment
	else
		local parentPart = targetAttachment.Parent
		if clone:IsA("Attachment") and parentPart then
			clone.Parent = parentPart
			clone.WorldCFrame = targetAttachment.WorldCFrame
		else
			clone.Parent = targetAttachment
		end
	end

	if clone:IsA("ParticleEmitter") then
		table.insert(emitters, clone)
	end
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			table.insert(emitters, descendant)
		end
	end

	self._activeSwordTip[player] = {
		token = token,
		instance = clone,
		emitters = emitters,
	}

	return #emitters > 0
end

function M1Service:_emitSwordTip(player: Player, token: number): boolean
	local state = self._activeSwordTip[player]
	if not state or state.token ~= token then
		return false
	end

	local emitted = false
	for _, emitter in ipairs(state.emitters) do
		if emitter and emitter.Parent then
			local emitCount = tonumber(emitter:GetAttribute("EmitCount")) or 1
			emitter:Emit(emitCount)
			emitted = true
		end
	end

	return emitted
end

function M1Service:_disableWeaponTrails(player: Player, token: number?)
	local activeTrails = self._activeWeaponTrails[player]
	if not activeTrails then
		return
	end
	if token ~= nil and activeTrails.token ~= token then
		return
	end

	for _, trail in ipairs(activeTrails.trails) do
		if trail and trail.Parent then
			trail.Enabled = false
		end
	end

	self._activeWeaponTrails[player] = nil
end

function M1Service:_enableWeaponTrails(player: Player, character: Model, tool: Tool, token: number)
	if self.Config.EnableWeaponTrails == false then
		return
	end

	self:_disableWeaponTrails(player)

	local trails = self:_collectWeaponTrails(character, tool)
	self._activeWeaponTrails[player] = {
		token = token,
		trails = trails,
	}
	self:_setWeaponTrailsEnabled(player, token, true)

	if #trails > 0 then
		return
	end

	if self.Config.UseBodyTrailFallback ~= true then
		return
	end
	if not self.Replication then
		return
	end

	local trailDuration = math.max(0.05, M1Calc.ToNumber(self.Config.FallbackBodyTrailDuration, 0.2))
	local trailLocation = tostring(self.Config.FallbackBodyTrailLocation or "BodyTrail1")
	self:_replicateGlobalEffectNear("BodyTrail", { character, trailDuration, trailLocation }, { character }, { player })
end

function M1Service:_replicateGlobalEffectNear(
	effectName: string,
	payload: any,
	contextCharacters: { Model }?,
	includePlayers: { Player }?
)
	if not self.Replication then
		return
	end

	local vfxRadius = math.max(0, M1Calc.ToNumber(self.Config.VfxReplicationRadius, 180))
	if self.CombatReplication and typeof(self.CombatReplication.FireClientsNear) == "function" then
		self.CombatReplication.FireClientsNear(
			self.Replication,
			"Global",
			effectName,
			payload,
			contextCharacters,
			vfxRadius,
			includePlayers
		)
		return
	end

	self.Replication:FireAllClients("Global", effectName, payload)
end

function M1Service:_markInCombat(player: Player, character: Model)
	local token = (self._combatTagToken[player] or 0) + 1
	self._combatTagToken[player] = token

	player:SetAttribute(ATTR.CombatTag, true)
	CollectionService:AddTag(player, ATTR.CombatTag)
	if character and character.Parent then
		character:SetAttribute(ATTR.CombatTag, true)
		CollectionService:AddTag(character, ATTR.CombatTag)
	end

	local duration = M1Calc.ToNumber(self.Config.CombatTagDuration, 45)
	task.delay(duration, function()
		if self._combatTagToken[player] ~= token then
			return
		end
		if player.Parent == Players then
			player:SetAttribute(ATTR.CombatTag, false)
			CollectionService:RemoveTag(player, ATTR.CombatTag)
			local char = player.Character
			if char and char.Parent then
				char:SetAttribute(ATTR.CombatTag, false)
				CollectionService:RemoveTag(char, ATTR.CombatTag)
			end
		end
	end)
end

function M1Service:_setSwingState(player: Player, character: Model, enabled: boolean)
	if character and character.Parent then
		character:SetAttribute(ATTR.Swing, enabled)
		character:SetAttribute(ATTR.Attacking, enabled)
	end

	if self.StateManager then
		self.StateManager.SetState(player, "Swinging", enabled)
	end
end

function M1Service:_releaseSwing(player: Player, character: Model, token: number)
	if self._activeAttackToken[player] ~= token then
		return
	end
	self._activeAttackToken[player] = nil

	if character and character.Parent then
		local currentToken = self._swingTokenByCharacter[character]
		if currentToken ~= token then
			return
		end
	end

	self:_setSwingState(player, character, false)
end

function M1Service:_nextCombo(player: Player, character: Model): number
	local now = os.clock()
	local combo, stamp = M1Calc.NextCombo(
		character,
		self._lastComboAt[player],
		self.Config.MaxCombo,
		self.Config.ComboResetTime,
		now,
		ATTR.Combo
	)
	self._lastComboAt[player] = stamp
	return combo
end

function M1Service:_scheduleComboReset(player: Player, character: Model)
	local token = (self._comboResetToken[player] or 0) + 1
	self._comboResetToken[player] = token

	local delaySeconds = math.max(0.1, M1Calc.ToNumber(self.Config.ComboResetTime, 2))
	task.delay(delaySeconds, function()
		if self._comboResetToken[player] ~= token then
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

		character:SetAttribute(ATTR.Combo, 1)
		self._lastComboAt[player] = nil
	end)
end

function M1Service:_initCharacter(player: Player, character: Model)
	self._activeAttackToken[player] = nil
	self._comboResetToken[player] = nil
	self:_disableWeaponTrails(player)
	self:_clearSwordTip(player)
	if self.HyperArmorService then
		self.HyperArmorService:Clear(character, nil, { replicate = true })
	end

	if character:GetAttribute(ATTR.Combo) == nil then
		character:SetAttribute(ATTR.Combo, 1)
	end
	if character:GetAttribute(ATTR.Swing) == nil then
		character:SetAttribute(ATTR.Swing, false)
	end
	if character:GetAttribute(ATTR.Attacking) == nil then
		character:SetAttribute(ATTR.Attacking, false)
	end
	if character:GetAttribute(ATTR.CombatTag) == nil then
		character:SetAttribute(ATTR.CombatTag, false)
	end
	player:SetAttribute(ATTR.CombatTag, false)
	CollectionService:RemoveTag(player, ATTR.CombatTag)
	CollectionService:RemoveTag(character, ATTR.CombatTag)

	self:_setSwingState(player, character, false)
	self._prewarmedToolByCharacter[character] = nil
	self:_bindCharacterPrewarm(player, character)
end

function M1Service:_cleanupPlayer(player: Player)
	self._lastSwingAt[player] = nil
	self._lastComboAt[player] = nil
	self._comboResetToken[player] = nil
	self._combatTagToken[player] = nil
	self._activeAttackToken[player] = nil
	self:_disableWeaponTrails(player)
	self:_clearSwordTip(player)
	player:SetAttribute(ATTR.CombatTag, false)
	CollectionService:RemoveTag(player, ATTR.CombatTag)
	local character = player.Character
	if character and character.Parent then
		if self.HyperArmorService then
			self.HyperArmorService:Clear(character, nil, { replicate = true })
		end
		character:SetAttribute(ATTR.CombatTag, false)
		CollectionService:RemoveTag(character, ATTR.CombatTag)
	end

	local conn = self._playerConns[player]
	if conn then
		conn:Disconnect()
		self._playerConns[player] = nil
	end

	self:_disconnectCharacterConns(player)
end

function M1Service:Init()
	local function bindPlayer(player: Player)
		if self._playerConns[player] then
			self._playerConns[player]:Disconnect()
			self._playerConns[player] = nil
		end

		self._playerConns[player] = player.CharacterAdded:Connect(function(character)
			self:_initCharacter(player, character)
		end)

		if player.Character then
			self:_initCharacter(player, player.Character)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
end

function M1Service:GetCombatHandler()
	return self._combatHandler
end

function M1Service:SetWeaponSpecialService(service: any)
	self.WeaponSpecialService = service
end

function M1Service:_isAirborneForSpecial(humanoid: Humanoid): boolean
	if humanoid.FloorMaterial == Enum.Material.Air then
		return true
	end

	local state = humanoid:GetState()
	return AIRBORNE_STATES[state] == true
end

function M1Service:_isRunningForSpecial(
	payload: any,
	humanoid: Humanoid,
	rootPart: BasePart,
	weaponStats: { [string]: any }
): boolean
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	if humanoid.MoveDirection.Magnitude <= 0 then
		return false
	end

	local moveHint = nil
	if typeof(payload) == "table" then
		moveHint = payload.moveHint
	end

	local hasRunningHint = false
	if typeof(moveHint) == "table" then
		hasRunningHint = moveHint.running == true or moveHint.wasRunning == true
	end

	local configMinMove = M1Calc.ToNumber(self.Config.RunningTriggerMinMove, 0.2)
	local minMove = math.max(0.01, M1Calc.ToNumber(weaponStats.RunningTriggerMinMove, configMinMove))
	if humanoid.MoveDirection.Magnitude < minMove then
		return false
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local configMinSpeed = M1Calc.ToNumber(self.Config.RunningTriggerMinSpeed, 11)
	local configHintMinSpeed = M1Calc.ToNumber(self.Config.RunningTriggerHintMinSpeed, 11)
	local minSpeed = math.max(0, M1Calc.ToNumber(weaponStats.RunningTriggerMinSpeed, configMinSpeed))
	local hintMinSpeed = math.max(0, M1Calc.ToNumber(weaponStats.RunningTriggerHintMinSpeed, configHintMinSpeed))

	local requiredSpeed = hasRunningHint and hintMinSpeed or minSpeed
	return planarSpeed >= requiredSpeed
end

function M1Service:_resolveM1SpecialAction(
	payload: any,
	_character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	weaponStats: { [string]: any }
): string?
	if not self.WeaponSpecialService then
		return nil
	end

	if self:_isAirborneForSpecial(humanoid) then
		return "Aerial"
	end

	if self:_isRunningForSpecial(payload, humanoid, rootPart, weaponStats) then
		return "Running"
	end

	return nil
end

function M1Service:_tryHandleWeaponSpecial(
	player: Player,
	payload: any,
	equippedTool: Tool,
	actionName: string
): (boolean, string?, boolean)
	local specialService = self.WeaponSpecialService
	if not specialService then
		return false, nil, false
	end

	local specialPayload = {
		toolName = equippedTool.Name,
		specialAction = actionName,
	}
	if typeof(payload) == "table" and typeof(payload.moveHint) == "table" then
		specialPayload.moveHint = payload.moveHint
	end

	if typeof(specialService.HandleActionRequest) == "function" then
		local ok, reason = specialService:HandleActionRequest(player, specialPayload, actionName)
		return ok, reason, true
	end

	if actionName ~= "Critical" then
		return false, "WeaponSpecialUnsupported", true
	end
	if typeof(specialService.HandleRequest) ~= "function" then
		return false, "WeaponSpecialUnsupported", true
	end

	local ok, reason = specialService:HandleRequest(player, specialPayload)
	return ok, reason, true
end

function M1Service:HandleRequest(player: Player, payload: any): (boolean, string?)
	local okValidation, validation = M1RequestValidator.ValidateRequest(player, payload, BLOCKED_SELF_ATTRS)
	if not okValidation then
		return false, validation
	end

	local character = validation.character
	local humanoid = validation.humanoid
	local rootPart = validation.rootPart
	local equippedTool = validation.equippedTool

	if self._activeAttackToken[player] ~= nil then
		return false, "AlreadyAttacking"
	end

	local weaponStats = self:_getWeaponStats(equippedTool.Name)
	local specialAction = self:_resolveM1SpecialAction(payload, character, humanoid, rootPart, weaponStats)
	if specialAction then
		local handled, specialReason, attempted =
			self:_tryHandleWeaponSpecial(player, payload, equippedTool, specialAction)
		if handled then
			return true
		end
		if attempted and specialReason ~= nil and not SPECIAL_FALLBACK_REASONS[specialReason] then
			return false, specialReason
		end
	end

	local waitBetweenHits = math.max(
		M1Calc.ToNumber(self.Config.MinSwingIntervalFloor, 0.065),
		M1Calc.ToNumber(weaponStats.WaitBetweenHits, 0.12)
	)
	local swordSwingPause = math.max(0, M1Calc.ToNumber(weaponStats.SwordSwingPause, 0))
	local swingSpeed = math.max(0.01, M1Calc.ToNumber(weaponStats.SwingSpeed, 1))

	local now = os.clock()
	local lastSwing = self._lastSwingAt[player]
	if lastSwing and (now - lastSwing) < waitBetweenHits then
		return false, "Cooldown"
	end
	self._lastSwingAt[player] = now

	local combo = self:_nextCombo(player, character)
	self:_scheduleComboReset(player, character)
	local damage = M1Calc.ResolveDamage(player, weaponStats.Damage)
	local swingAnimation = M1Anims.ResolveSwingAnimation(self.AssetsRoot, equippedTool.Name, combo)

	local maxCombo = math.max(1, math.floor(M1Calc.ToNumber(self.Config.MaxCombo, 4)))
	local comboFinishPause = combo >= maxCombo and math.max(0, M1Calc.ToNumber(self.Config.ComboFinishPause, 0.5)) or 0
	local statePadding = math.max(0, M1Calc.ToNumber(self.Config.StateReleasePadding, 0.04))

	local token = (self._swingTokenByCharacter[character] or 0) + 1
	self._swingTokenByCharacter[character] = token
	self._activeAttackToken[player] = token
	self:_enableWeaponTrails(player, character, equippedTool, token)
	local hasSwordTip = self:_spawnSwordTip(player, character, equippedTool, token)

	local slowWalkSpeed = math.max(0, M1Calc.ToNumber(self.Config.AttackWalkSpeed, 6))
	local restoreWalkSpeed = math.max(0, M1Calc.ToNumber(self.Config.RestoreWalkSpeed, 9))
	if humanoid.WalkSpeed > slowWalkSpeed then
		humanoid.WalkSpeed = slowWalkSpeed
	end

	self:_setSwingState(player, character, true)
	character:SetAttribute("Running", false)

	local hitTriggered = false
	local hitUnlockAt: number? = nil
	local hasTrack = false
	local swordTipEmitted = false

	local function emitSwordTipOnce()
		if swordTipEmitted or not hasSwordTip then
			return
		end
		if self._activeAttackToken[player] ~= token then
			return
		end
		swordTipEmitted = self:_emitSwordTip(player, token) or swordTipEmitted
	end

	if hasSwordTip then
		local emitDelay = math.max(0, swordSwingPause)
		task.delay(emitDelay, function()
			emitSwordTipOnce()
		end)
	end

	local function triggerHit()
		if hitTriggered then
			return
		end
		if self._activeAttackToken[player] ~= token then
			return
		end
		-- If defense becomes active before the hit frame, cancel this swing hit.
		if
			character:GetAttribute("Parrying") == true
			or character:GetAttribute("isBlocking") == true
			or character:GetAttribute("AutoParryActive") == true
		then
			hitTriggered = true
			return
		end
		hitTriggered = true
		self._combatHandler:SpawnHitbox(player, character, rootPart, combo, weaponStats, damage, equippedTool.Name)
	end

	local releaseScheduled = false
	local function scheduleRelease(delaySeconds: number)
		if releaseScheduled then
			return
		end
		releaseScheduled = true

		task.delay(math.max(0, delaySeconds), function()
			if character and character.Parent and humanoid and humanoid.Parent then
				local blockedRestore = character:GetAttribute("Stunned") == true
					or character:GetAttribute("SlowStunned") == true
					or character:GetAttribute("IsRagdoll") == true
					or character:GetAttribute("Downed") == true
				if not blockedRestore then
					humanoid.WalkSpeed = restoreWalkSpeed
				end
			end

			self:_disableWeaponTrails(player, token)
			self:_clearSwordTip(player, token, 2)
			self:_releaseSwing(player, character, token)
		end)
	end

	local function onHitPhase()
		if self._activeAttackToken[player] ~= token then
			return
		end
		if not character or not character.Parent then
			return
		end

		character:SetAttribute(ATTR.Attacking, false)
		triggerHit()

		if hitUnlockAt == nil then
			hitUnlockAt = os.clock() + waitBetweenHits + comboFinishPause + statePadding
		end

		if not hasTrack then
			local remaining = math.max(0, (hitUnlockAt or os.clock()) - os.clock())
			scheduleRelease(remaining)
		end
	end

	if swingAnimation then
		local track = self.AnimUtil.LoadTrack(humanoid, swingAnimation, ("M1Swing%d"):format(combo))
		if track then
			hasTrack = true
			track.Priority = self.Config.AttackTrackPriority
			track:Play(M1Calc.ToNumber(self.Config.AttackTrackFadeTime, 0.04))
			track:AdjustSpeed(swingSpeed)

			local keyframeConn: RBXScriptConnection? = nil
			local holdUsed = false
			local function playSwingSound()
				self:_playToolSound(character, equippedTool.Name, { "swing1", "swing2" }, rootPart)
			end

			keyframeConn = track.KeyframeReached:Connect(function(keyframeName)
				local key = string.lower(tostring(keyframeName))
				if TRAIL_START_KEYFRAMES[key] then
					self:_setWeaponTrailsEnabled(player, token, true)
				elseif TRAIL_END_KEYFRAMES[key] then
					self:_setWeaponTrailsEnabled(player, token, false)
				end

				if SWORD_TIP_KEYFRAMES[key] then
					emitSwordTipOnce()
				end

				if key == "hold" and not holdUsed then
					holdUsed = true
					if swordSwingPause > 0 then
						track:AdjustSpeed(0)
						task.delay(swordSwingPause, function()
							if self._swingTokenByCharacter[character] ~= token then
								return
							end
							if not track.IsPlaying then
								return
							end
							emitSwordTipOnce()
							playSwingSound()
							track:AdjustSpeed(swingSpeed)
						end)
					else
						emitSwordTipOnce()
						playSwingSound()
					end
					return
				end

				if key == "hit" then
					onHitPhase()
				end
			end)

			track.Stopped:Connect(function()
				if keyframeConn and keyframeConn.Connected then
					keyframeConn:Disconnect()
				end

				self:_setWeaponTrailsEnabled(player, token, false)
				self:_clearSwordTip(player, token, 2)

				if not hitTriggered then
					onHitPhase()
				end
				local remaining = 0
				if hitUnlockAt ~= nil then
					remaining = math.max(0, hitUnlockAt - os.clock())
				end
				scheduleRelease(remaining)
			end)
		end
	end

	if not hasTrack then
		task.delay(math.max(0.02, M1Calc.ToNumber(self.Config.HitboxFallbackDelay, 0.1)), onHitPhase)
	end

	return true
end

return M1Service
