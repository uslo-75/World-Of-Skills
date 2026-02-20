local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function resolveCombatRoot(): Instance
	local combatRoot = script:FindFirstAncestor("Combat")
	if combatRoot then
		return combatRoot
	end

	error(("[CriticalService] Combat root not found from %s"):format(script:GetFullName()))
end

local combatRoot = resolveCombatRoot()
local m1ServiceRoot = combatRoot:WaitForChild("M1"):WaitForChild("M1Service")
local M1Calc = require(m1ServiceRoot:WaitForChild("M1Calc"))
local M1Anims = require(m1ServiceRoot:WaitForChild("M1Anims"))
local M1Queries = require(m1ServiceRoot:WaitForChild("M1Queries"))
local SkillAnimUtil = require(
	combatRoot:WaitForChild("WeaponSpecials"):WaitForChild("Shared"):WaitForChild("SkillAnimUtil")
)
local CombatWeaponUtil = require(combatRoot:WaitForChild("Shared"):WaitForChild("CombatWeaponUtil"))
local CombatNet = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatNet"))

local function resolveLocalModule(moduleName: string): ModuleScript
	local asChild = script:FindFirstChild(moduleName)
	if asChild and asChild:IsA("ModuleScript") then
		return asChild
	end

	local parent = script.Parent
	if parent then
		local asSibling = parent:FindFirstChild(moduleName)
		if asSibling and asSibling:IsA("ModuleScript") then
			return asSibling
		end
	end

	error(("[CriticalService] Module '%s' not found near %s"):format(moduleName, script:GetFullName()))
end

local CriticalConstants = require(resolveLocalModule("CriticalConstants"))
local CriticalRequestValidator = require(resolveLocalModule("CriticalRequestValidator"))

local ATTR = CriticalConstants.Attributes
local BLOCKED_SELF_ATTRS = CriticalConstants.BlockedSelfAttrs

local DEFAULT_SETTINGS = table.freeze({
	MinUseIntervalFloor = 0.1,
	HitboxActiveTime = 0.1,
	HitboxFallbackDelay = 0.12,
	StateReleasePadding = 0.06,
	AttackTrackFadeTime = 0.04,
	AttackTrackPriority = Enum.AnimationPriority.Action3,
	DefaultSwingSpeed = 1.25,
	AttackWalkSpeed = 4,
	RestoreWalkSpeed = 9,
	DefaultCooldown = 6,
	DefaultWeaponFolder = "Default",
})

local ACTION_DEFS = table.freeze({
	Critical = table.freeze({
		name = "Critical",
		cooldownAttr = ATTR.Cooldown,
		cooldownTimeAttr = ATTR.CooldownTime,
	}),
	Aerial = table.freeze({
		name = "Aerial",
		cooldownAttr = "AerialCooldown",
		cooldownTimeAttr = "AerialCooldownTime",
	}),
	Running = table.freeze({
		name = "Running",
		cooldownAttr = "RunningCooldown",
		cooldownTimeAttr = "RunningCooldownTime",
	}),
	Strikefall = table.freeze({
		name = "Strikefall",
		cooldownAttr = "StrikefallCooldown",
		cooldownTimeAttr = "StrikefallCooldownTime",
	}),
	RendStep = table.freeze({
		name = "RendStep",
		cooldownAttr = "RendStepCooldown",
		cooldownTimeAttr = "RendStepCooldownTime",
	}),
	AnchoringStrike = table.freeze({
		name = "AnchoringStrike",
		cooldownAttr = "AnchoringStrikeCooldown",
		cooldownTimeAttr = "AnchoringStrikeCooldownTime",
	}),
})

local ACTION_ALIAS_BY_KEY = table.freeze({
	critical = "Critical",
	aerial = "Aerial",
	running = "Running",
	strikefall = "Strikefall",
	rendstep = "RendStep",
	anchoringstrike = "AnchoringStrike",
})

local SKILL_KEY_BY_CODE = table.freeze({
	Z = "Z",
	z = "Z",
	X = "X",
	x = "X",
	C = "C",
	c = "C",
	V = "V",
	v = "V",
})

local SKILL_PREWARM_ANIMATION_CANDIDATES = table.freeze({
	Strikefall = table.freeze({
		"MeleCharge",
		"Strikefall",
		"MeleHit",
		"StrikefallCombo",
	}),
	RendStep = table.freeze({
		"MeleStartUp",
		"RendStep",
		"MeleStartUpMiss",
		"RendStepMiss",
		"MeleStartUpHit",
		"RendStepHit",
	}),
	AnchoringStrike = table.freeze({
		"AnchoringStrike",
	}),
})

local CriticalService = {}
CriticalService.__index = CriticalService

local function cleanupInstance(inst: Instance?)
	if inst and inst.Parent then
		inst:Destroy()
	end
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

local function mergeSettings(customSettings: { [string]: any }?): { [string]: any }
	local merged = {}
	for key, value in pairs(DEFAULT_SETTINGS) do
		merged[key] = value
	end

	if typeof(customSettings) == "table" then
		for key, value in pairs(customSettings) do
			merged[key] = value
		end
	end

	return merged
end

local function normalizeActionName(raw: any): string
	if typeof(raw) ~= "string" then
		return "Critical"
	end

	local key = string.lower(raw):gsub("[%s_%-%./]", "")
	local canonical = ACTION_ALIAS_BY_KEY[key]
	if canonical then
		return canonical
	end

	return "Critical"
end

function CriticalService.new(deps)
	local self = setmetatable({}, CriticalService)

	self.Settings = mergeSettings(deps.Settings)
	self.StateManager = deps.StateManager
	self.AnimUtil = deps.AnimUtil
	self.SoundUtil = deps.SoundUtil
	self.AssetsRoot = deps.AssetsRoot or ReplicatedStorage
	self.WeaponInfo = deps.WeaponInfo
	self.HitboxModule = deps.HitboxModule
	self.CombatHandler = deps.CombatHandler
	self.WeaponsRoot = deps.WeaponsRoot
	self.SkillsRoot = deps.SkillsRoot
	self.HyperArmorService = deps.HyperArmorService

	self.M1Calc = M1Calc
	self.M1Anims = M1Anims
	self.CombatNet = CombatNet

	self._playerConns = {} -- [Player] = RBXScriptConnection
	self._characterConns = {} -- [Player] = { RBXScriptConnection }
	self._activeAttackToken = {} -- [Player] = number?
	self._attackTokenByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = number
	self._cooldownToken = {} -- [Player] = { [string]: number }
	self._lastUseAt = {} -- [Player] = os.clock()
	self._forwardVelocityByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = { attachment = Attachment, velocity = LinearVelocity }
	self._weaponHandlerByScript = setmetatable({}, { __mode = "k" }) -- [ModuleScript] = any
	self._weaponHandlerLoadFailed = setmetatable({}, { __mode = "k" }) -- [ModuleScript] = true
	self._prewarmedToolByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = { [string] = true }

	return self
end

function CriticalService:_resolveCombatHandler()
	return self.CombatHandler
end

function CriticalService:_resolveActionDef(actionName: any)
	local normalized = normalizeActionName(actionName)
	return ACTION_DEFS[normalized], normalized
end

function CriticalService:_getWeaponStats(toolName: string): { [string]: any }
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

function CriticalService:_normalizeSkillKey(raw: any): string?
	if typeof(raw) ~= "string" then
		return nil
	end

	return SKILL_KEY_BY_CODE[raw]
end

function CriticalService:_resolveSkillNameFromPayload(weaponStats: { [string]: any }, payload: any): (string?, string?)
	if typeof(payload) ~= "table" then
		return nil, "InvalidPayload"
	end

	local rawSkillKey = payload.skillKey
	if rawSkillKey == nil then
		rawSkillKey = payload.key
	end
	if rawSkillKey == nil then
		rawSkillKey = payload.k
	end

	local skillKey = self:_normalizeSkillKey(rawSkillKey)
	if not skillKey then
		return nil, "InvalidSkillKey"
	end

	local skillName = weaponStats[skillKey]
	if typeof(skillName) ~= "string" then
		return nil, "SkillNotConfigured"
	end

	local trimmed = skillName:match("^%s*(.-)%s*$")
	if trimmed == "" or string.lower(trimmed) == "none" then
		return nil, "SkillNotConfigured"
	end

	local normalizedSkillName = normalizeActionName(trimmed)
	if normalizedSkillName == "Critical" and string.lower(trimmed) ~= "critical" then
		return nil, "SkillNotSupported"
	end

	return normalizedSkillName, nil
end

function CriticalService:_resolveWeaponSoundNames(character: Model?, fallbackToolName: string?): { string }
	return CombatWeaponUtil.CollectWeaponSoundNames(character, fallbackToolName, M1Queries.GetSelectedAttackTool)
end

function CriticalService:PlayWeaponSound(character: Model?, fallbackToolName: string?, soundNames: any, parent: Instance?)
	if not self.SoundUtil or typeof(self.SoundUtil.PlayTool) ~= "function" then
		return
	end

	local weaponNames = self:_resolveWeaponSoundNames(character, fallbackToolName)
	if #weaponNames == 0 then
		return
	end

	self.SoundUtil.PlayTool(self.AssetsRoot, weaponNames, soundNames, parent)
end

function CriticalService:_setAttackState(player: Player, character: Model, enabled: boolean)
	if character and character.Parent then
		character:SetAttribute(ATTR.Swing, enabled)
		character:SetAttribute(ATTR.Attacking, enabled)
	end

	if self.StateManager and typeof(self.StateManager.SetState) == "function" then
		self.StateManager.SetState(player, "Swinging", enabled)
	end
end

function CriticalService:_releaseAttack(player: Player, character: Model, token: number)
	if self._activeAttackToken[player] ~= token then
		return
	end
	self._activeAttackToken[player] = nil

	if character and character.Parent then
		local currentToken = self._attackTokenByCharacter[character]
		if currentToken ~= token then
			return
		end
	end

	self:_setAttackState(player, character, false)
end

function CriticalService:_stopForwardVelocity(character: Model)
	local state = self._forwardVelocityByCharacter[character]
	if not state then
		return
	end

	cleanupInstance(state.velocity)
	cleanupInstance(state.attachment)
	self._forwardVelocityByCharacter[character] = nil
end

function CriticalService:PushForward(character: Model, speed: number, duration: number)
	if speed <= 0 then
		return
	end
	if duration <= 0 then
		return
	end
	if not character or not character.Parent then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local flatDirection = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if flatDirection.Magnitude <= 0 then
		return
	end

	self:PushVelocity(character, flatDirection.Unit * speed, duration, math.max(1200, speed * 1500))
end

function CriticalService:PushVelocity(character: Model, worldVelocity: Vector3, duration: number, maxForce: number?)
	self:_stopForwardVelocity(character)
	if duration <= 0 then
		return
	end
	if not character or not character.Parent then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "__CriticalForwardAttachment"
	attachment.Parent = rootPart

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "__CriticalForwardVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.max(1200, M1Calc.ToNumber(maxForce, worldVelocity.Magnitude * 1500))
	velocity.VectorVelocity = worldVelocity
	velocity.Parent = rootPart

	self._forwardVelocityByCharacter[character] = {
		attachment = attachment,
		velocity = velocity,
	}

	task.delay(duration, function()
		local latest = self._forwardVelocityByCharacter[character]
		if latest and latest.velocity == velocity then
			self:_stopForwardVelocity(character)
		end
	end)
end

function CriticalService:_isRestoreBlocked(character: Model): boolean
	return character:GetAttribute("Stunned") == true
		or character:GetAttribute("SlowStunned") == true
		or character:GetAttribute("IsRagdoll") == true
		or character:GetAttribute("Downed") == true
end

function CriticalService:_restoreWalkSpeed(character: Model, humanoid: Humanoid?)
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

	hum.WalkSpeed = math.max(0, M1Calc.ToNumber(self.Settings.RestoreWalkSpeed, 9))
end

function CriticalService:_isOnCooldown(character: Model, actionName: any): boolean
	local actionDef = self:_resolveActionDef(actionName)
	return character:GetAttribute(actionDef.cooldownAttr) == true
end

function CriticalService:_startCooldown(player: Player, character: Model, duration: number, actionName: any)
	local actionDef = self:_resolveActionDef(actionName)
	local cooldownDuration = math.max(0, duration)
	local tokensByAttr = self._cooldownToken[player]
	if not tokensByAttr then
		tokensByAttr = {}
		self._cooldownToken[player] = tokensByAttr
	end

	local attrName = actionDef.cooldownAttr
	local attrTimeName = actionDef.cooldownTimeAttr
	local token = (tokensByAttr[attrName] or 0) + 1
	tokensByAttr[attrName] = token

	character:SetAttribute(attrName, true)
	character:SetAttribute(attrTimeName, cooldownDuration)

	task.delay(cooldownDuration, function()
		local liveTokensByAttr = self._cooldownToken[player]
		if not liveTokensByAttr then
			return
		end
		if liveTokensByAttr[attrName] ~= token then
			return
		end
		if player.Parent ~= Players then
			return
		end

		local liveCharacter = player.Character
		if not liveCharacter or not liveCharacter.Parent then
			return
		end

		liveCharacter:SetAttribute(attrName, nil)
		liveCharacter:SetAttribute(attrTimeName, nil)
		liveTokensByAttr[attrName] = nil
		if next(liveTokensByAttr) == nil then
			self._cooldownToken[player] = nil
		end
	end)
end

function CriticalService:StartAttack(context: { [string]: any }, options: { [string]: any }?): (number?, string?)
	local player: Player = context.player
	local character: Model = context.character
	local humanoid: Humanoid = context.humanoid
	local actionName = (options and options.actionName) or context.actionName
	local cooldownDuration = M1Calc.ToNumber((options and options.cooldownDuration), self.Settings.DefaultCooldown)

	if self._activeAttackToken[player] ~= nil then
		return nil, "AlreadyAttacking"
	end

	local token = (self._attackTokenByCharacter[character] or 0) + 1
	self._attackTokenByCharacter[character] = token
	self._activeAttackToken[player] = token
	self:_setAttackState(player, character, true)
	self:_startCooldown(player, character, cooldownDuration, actionName)

	character:SetAttribute("Running", false)
	if self.StateManager and typeof(self.StateManager.SetState) == "function" then
		self.StateManager.SetState(player, "Running", false)
	end

	local attackWalkSpeed = math.max(0, M1Calc.ToNumber((options and options.attackWalkSpeed), self.Settings.AttackWalkSpeed))
	if humanoid.WalkSpeed > attackWalkSpeed then
		humanoid.WalkSpeed = attackWalkSpeed
	end

	return token, nil
end

function CriticalService:IsAttackTokenCurrent(player: Player, token: number): boolean
	return self._activeAttackToken[player] == token
end

function CriticalService:FinishAttack(player: Player, character: Model, humanoid: Humanoid?, token: number)
	if character and character.Parent then
		self:_stopForwardVelocity(character)
		self:_restoreWalkSpeed(character, humanoid)
	end
	self:_releaseAttack(player, character, token)
end

function CriticalService:ScheduleFinish(player: Player, character: Model, humanoid: Humanoid?, token: number, delaySeconds: number)
	task.delay(math.max(0, delaySeconds), function()
		self:FinishAttack(player, character, humanoid, token)
	end)
end

function CriticalService:ResolveActionAnimation(
	character: Model,
	toolName: string,
	actionName: any,
	comboForFallback: number?
): Animation?
	local normalizedActionName = normalizeActionName(actionName)
	local animation = M1Anims.ResolveWeaponAttackAnimation(self.AssetsRoot, toolName, normalizedActionName)
	if animation then
		return animation
	end

	if normalizedActionName ~= "Critical" then
		animation = M1Anims.ResolveCriticalAnimation(self.AssetsRoot, toolName)
		if animation then
			return animation
		end
	end

	local combo = math.max(1, math.floor(M1Calc.ToNumber(comboForFallback, 4)))
	local fallbackToolName = toolName
	if fallbackToolName == nil or fallbackToolName == "" then
		local selectedTool = M1Queries.GetSelectedAttackTool(character)
		if selectedTool then
			fallbackToolName = selectedTool.Name
		end
	end
	if not fallbackToolName then
		return nil
	end

	return M1Anims.ResolveSwingAnimation(self.AssetsRoot, fallbackToolName, combo)
end

function CriticalService:ResolveCriticalAnimation(character: Model, toolName: string, comboForFallback: number?): Animation?
	return self:ResolveActionAnimation(character, toolName, "Critical", comboForFallback)
end

function CriticalService:SpawnHitbox(args: { [string]: any })
	if not self.HitboxModule then
		return
	end
	local combatHandler = self:_resolveCombatHandler()
	if not combatHandler or typeof(combatHandler.ApplyHit) ~= "function" then
		return
	end

	local player: Player = args.player
	local character: Model = args.character
	local rootPart: BasePart = args.rootPart
	local weaponStats = args.weaponStats or {}
	local attackerToolName: string? = args.attackerToolName
	local damage = math.max(0, M1Calc.ToNumber(args.damage, 0))
	local hitProfile = args.hitProfile
	local hitboxSize = args.hitboxSize
	local hitboxOffset = args.hitboxOffset
	local onHitCallback = args.onHit
	local onContactCallback = args.onContact

	local hitbox = self.HitboxModule.new(player)
	if not hitbox then
		return
	end

	local size = hitboxSize
	if typeof(size) ~= "Vector3" then
		size = weaponStats.HeavyHitboxSize
	end
	if typeof(size) ~= "Vector3" then
		size = Vector3.new(12, 8, 12)
	end

	local offset = hitboxOffset
	if typeof(offset) ~= "CFrame" then
		offset = weaponStats.HeavyHitboxOffset
	end
	if typeof(offset) ~= "CFrame" then
		offset = CFrame.new(0, 0, -1.6)
	end

	local comboForReaction = 4
	if typeof(hitProfile) == "table" then
		comboForReaction = math.max(1, math.floor(M1Calc.ToNumber(hitProfile.comboForReaction, comboForReaction)))
	end

	hitbox.Size = size
	hitbox.Offset = offset
	hitbox.Instance = rootPart
	hitbox.Ignore = { character }
	hitbox.ResetCharactersList = false

	local touched = {}
	hitbox.onTouch = function(enemyCharacter: Model)
		if touched[enemyCharacter] then
			return
		end
		touched[enemyCharacter] = true
		local didHit = combatHandler:ApplyHit(
			player,
			character,
			rootPart,
			enemyCharacter,
			comboForReaction,
			weaponStats,
			damage,
			attackerToolName,
			hitProfile
		)

		if typeof(onContactCallback) == "function" then
			task.defer(onContactCallback, enemyCharacter, didHit)
		end

		if didHit == true and typeof(onHitCallback) == "function" then
			task.defer(onHitCallback, enemyCharacter)
		end
	end

	local activeTime = math.max(0.03, M1Calc.ToNumber(args.activeTime, self.Settings.HitboxActiveTime))
	hitbox:Start(activeTime, true)
end

function CriticalService:ReplicateWeaponaryEffect(
	effectName: string,
	payload: any,
	contextCharacters: any,
	includePlayers: { Player }?
)
	local combatHandler = self:_resolveCombatHandler()
	if not combatHandler then
		return
	end

	local replicateFn = combatHandler.ReplicateWeaponaryEffect
	if typeof(replicateFn) ~= "function" then
		return
	end

	replicateFn(combatHandler, effectName, payload, contextCharacters, includePlayers)
end

function CriticalService:_collectWeaponFolderNames(character: Model, equippedTool: Tool): { string }
	return CombatWeaponUtil.CollectToolNameCandidates(character, equippedTool)
end

function CriticalService:_resolveActionModuleScript(folder: Instance?, actionName: string): ModuleScript?
	if not folder or not folder:IsA("Folder") then
		return nil
	end
	local scriptName = tostring(actionName)
	local moduleScript = folder:FindFirstChild(scriptName)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		return moduleScript
	end
	return nil
end

function CriticalService:_resolveSkillModuleScript(actionName: string): ModuleScript?
	local root = self.SkillsRoot
	if not root or not root:IsA("Folder") then
		return nil
	end

	local entry = root:FindFirstChild(tostring(actionName))
	if not entry then
		return nil
	end

	if entry:IsA("ModuleScript") then
		return entry
	end

	if entry:IsA("Folder") then
		local initModule = entry:FindFirstChild("init")
		if initModule and initModule:IsA("ModuleScript") then
			return initModule
		end

		local namedModule = entry:FindFirstChild(tostring(actionName))
		if namedModule and namedModule:IsA("ModuleScript") then
			return namedModule
		end
	end

	return nil
end

function CriticalService:_requireHandler(moduleScript: ModuleScript): any
	if self._weaponHandlerByScript[moduleScript] ~= nil then
		return self._weaponHandlerByScript[moduleScript]
	end
	if self._weaponHandlerLoadFailed[moduleScript] then
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(("[CriticalService] Failed to load handler '%s': %s"):format(moduleScript:GetFullName(), tostring(result)))
		self._weaponHandlerLoadFailed[moduleScript] = true
		return nil
	end

	if typeof(result) ~= "table" and typeof(result) ~= "function" then
		warn(("[CriticalService] Invalid handler type in '%s'"):format(moduleScript:GetFullName()))
		self._weaponHandlerLoadFailed[moduleScript] = true
		return nil
	end

	self._weaponHandlerByScript[moduleScript] = result
	return result
end

function CriticalService:_resolveActionHandler(character: Model, equippedTool: Tool, actionName: string): any
	local skillModuleScript = self:_resolveSkillModuleScript(actionName)
	if skillModuleScript then
		local skillHandler = self:_requireHandler(skillModuleScript)
		if skillHandler ~= nil then
			return skillHandler
		end
	end

	local root = self.WeaponsRoot
	if not root or not root:IsA("Folder") then
		return nil
	end

	for _, folderName in ipairs(self:_collectWeaponFolderNames(character, equippedTool)) do
		local weaponFolder = root:FindFirstChild(folderName)
		local moduleScript = self:_resolveActionModuleScript(weaponFolder, actionName)
		if moduleScript then
			local handler = self:_requireHandler(moduleScript)
			if handler ~= nil then
				return handler
			end
		end
	end

	local defaultFolder = root:FindFirstChild(tostring(self.Settings.DefaultWeaponFolder or "Default"))
	local defaultModuleScript = self:_resolveActionModuleScript(defaultFolder, actionName)
	if not defaultModuleScript then
		return nil
	end

	return self:_requireHandler(defaultModuleScript)
end

function CriticalService:_prewarmActionHandlers(character: Model, equippedTool: Tool)
	if not character or not character.Parent then
		return
	end
	if not equippedTool or equippedTool.Parent ~= character then
		return
	end
	if not M1Queries.IsAttackTool(equippedTool) then
		return
	end

	local cacheByToolName = self._prewarmedToolByCharacter[character]
	if not cacheByToolName then
		cacheByToolName = {}
		self._prewarmedToolByCharacter[character] = cacheByToolName
	end

	local toolNames = self:_collectWeaponFolderNames(character, equippedTool)
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

	for _, actionDef in pairs(ACTION_DEFS) do
		self:_resolveActionHandler(character, equippedTool, actionDef.name)
	end

	self:_prewarmActionAnimations(character, equippedTool)

	for _, toolName in ipairs(toolNames) do
		cacheByToolName[toolName] = true
	end
end

function CriticalService:_collectPrewarmAnimations(character: Model, equippedTool: Tool): { Animation }
	local animations = {}
	local seen: { [Animation]: boolean } = {}
	local comboForFallback = 4

	for _, actionDef in pairs(ACTION_DEFS) do
		local animation = self:ResolveActionAnimation(character, equippedTool.Name, actionDef.name, comboForFallback)
		addAnimationUnique(animations, seen, animation)
	end

	for _, candidates in pairs(SKILL_PREWARM_ANIMATION_CANDIDATES) do
		for _, candidate in ipairs(candidates) do
			addAnimationUnique(animations, seen, SkillAnimUtil.ResolveSkillAnimation(self, { candidate }))
		end
	end

	return animations
end

function CriticalService:_prewarmActionAnimations(character: Model, equippedTool: Tool)
	if not self.AnimUtil or typeof(self.AnimUtil.LoadTrack) ~= "function" then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	for _, animation in ipairs(self:_collectPrewarmAnimations(character, equippedTool)) do
		local ok, track = pcall(self.AnimUtil.LoadTrack, humanoid, animation, "__CriticalPrewarm")
		if ok and track then
			pcall(function()
				track:Stop(0)
			end)
			pcall(function()
				track:Destroy()
			end)
		end
	end
end

function CriticalService:_disconnectCharacterConns(player: Player)
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

function CriticalService:_bindCharacterPrewarm(player: Player, character: Model)
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
				self:_prewarmActionHandlers(character, selected)
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
		if not tool then
			return
		end

		self:_prewarmActionHandlers(character, tool)
	end

	table.insert(conns, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			tryPrewarmFromInstance(child)
			scheduleSelectedPrewarm()
		end
	end))

	table.insert(conns, character.DescendantAdded:Connect(function(inst)
		if inst.Name == "EquipedWeapon" then
			tryPrewarmFromInstance(inst)
			scheduleSelectedPrewarm()
		end
	end))

	table.insert(conns, character:GetAttributeChangedSignal("Weapon"):Connect(scheduleSelectedPrewarm))

	scheduleSelectedPrewarm()
end

function CriticalService:_executeActionHandler(handler: any, context: { [string]: any }): (boolean, string?)
	local executeFn = nil
	if typeof(handler) == "function" then
		executeFn = handler
	elseif typeof(handler) == "table" and typeof(handler.Execute) == "function" then
		executeFn = handler.Execute
	end

	if not executeFn then
		return false, "InvalidWeaponHandler"
	end

	local function forceReleaseIfStuck(reason: string)
		local player = context and context.player
		local character = context and context.character
		local humanoid = context and context.humanoid
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end

		local token = self._activeAttackToken[player]
		if token == nil then
			return
		end

		warn(
			("[CriticalService] Emergency release (%s) player=%s action=%s token=%s"):format(
				reason,
				player.Name,
				tostring(context and context.actionName),
				tostring(token)
			)
		)
		self:FinishAttack(player, character, humanoid, token)
	end

	local ok, result, reason = pcall(executeFn, self, context)
	if not ok then
		warn(("[CriticalService] Weapon handler execution failed: %s"):format(tostring(result)))
		forceReleaseIfStuck("handler_error")
		return false, "CriticalHandlerError"
	end

	if typeof(result) == "boolean" then
		if result == false then
			forceReleaseIfStuck("handler_return_false")
		end
		return result, reason
	end

	forceReleaseIfStuck("invalid_handler_result")
	return false, "InvalidWeaponHandlerResult"
end

function CriticalService:_initCharacter(player: Player, character: Model)
	self._activeAttackToken[player] = nil
	self._cooldownToken[player] = nil
	self:_stopForwardVelocity(character)
	for _, actionDef in pairs(ACTION_DEFS) do
		character:SetAttribute(actionDef.cooldownAttr, nil)
		character:SetAttribute(actionDef.cooldownTimeAttr, nil)
	end
	self._prewarmedToolByCharacter[character] = nil
	self:_bindCharacterPrewarm(player, character)
end

function CriticalService:_cleanupPlayer(player: Player)
	self._activeAttackToken[player] = nil
	self._cooldownToken[player] = nil
	self._lastUseAt[player] = nil

	local character = player.Character
	if character and character.Parent then
		self:_stopForwardVelocity(character)
		for _, actionDef in pairs(ACTION_DEFS) do
			character:SetAttribute(actionDef.cooldownAttr, nil)
			character:SetAttribute(actionDef.cooldownTimeAttr, nil)
		end
	end

	local conn = self._playerConns[player]
	if conn then
		conn:Disconnect()
		self._playerConns[player] = nil
	end

	self:_disconnectCharacterConns(player)
end

function CriticalService:Init()
	local function bindPlayer(player: Player)
		local existing = self._playerConns[player]
		if existing then
			existing:Disconnect()
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

function CriticalService:HandleActionRequest(player: Player, payload: any, forcedActionName: any): (boolean, string?)
	local okValidation, validation = CriticalRequestValidator.ValidateRequest(player, payload, BLOCKED_SELF_ATTRS)
	if not okValidation then
		return false, validation
	end

	local character = validation.character
	local equippedTool = validation.equippedTool
	local combatHandler = self:_resolveCombatHandler()
	if not combatHandler or typeof(combatHandler.ApplyHit) ~= "function" then
		return false, "CombatHandlerMissing"
	end

	local _, actionName = self:_resolveActionDef(forcedActionName or (payload and payload.specialAction) or (payload and payload.actionName))

	if self._activeAttackToken[player] ~= nil then
		return false, "AlreadyAttacking"
	end
	if self:_isOnCooldown(character, actionName) then
		return false, "Cooldown"
	end

	local now = os.clock()
	local minInterval = math.max(0.05, M1Calc.ToNumber(self.Settings.MinUseIntervalFloor, 0.1))
	local lastUseAt = self._lastUseAt[player]
	if lastUseAt and (now - lastUseAt) < minInterval then
		return false, "Cooldown"
	end
	self._lastUseAt[player] = now
	self:_prewarmActionHandlers(character, equippedTool)

	local context = {
		player = player,
		payload = payload,
		actionName = actionName,
		character = validation.character,
		humanoid = validation.humanoid,
		rootPart = validation.rootPart,
		equippedTool = validation.equippedTool,
		weaponStats = self:_getWeaponStats(equippedTool.Name),
	}

	local handler = self:_resolveActionHandler(character, equippedTool, actionName)
	if not handler then
		return false, "WeaponModuleMissing"
	end

	return self:_executeActionHandler(handler, context)
end

function CriticalService:HandleSkillRequest(player: Player, payload: any): (boolean, string?)
	local okValidation, validation = CriticalRequestValidator.ValidateRequest(player, payload, BLOCKED_SELF_ATTRS)
	if not okValidation then
		return false, validation
	end

	local equippedTool = validation.equippedTool
	local weaponStats = self:_getWeaponStats(equippedTool.Name)
	if next(weaponStats) == nil then
		local alias = equippedTool:GetAttribute("Weapon")
		if typeof(alias) == "string" and alias ~= "" then
			weaponStats = self:_getWeaponStats(alias)
		end
	end
	if next(weaponStats) == nil then
		local displayName = equippedTool:GetAttribute("Name")
		if typeof(displayName) == "string" and displayName ~= "" then
			weaponStats = self:_getWeaponStats(displayName)
		end
	end

	local skillName, skillErr = self:_resolveSkillNameFromPayload(weaponStats, payload)
	if not skillName then
		return false, skillErr
	end

	local normalizedPayload = {}
	if typeof(payload) == "table" then
		for key, value in pairs(payload) do
			normalizedPayload[key] = value
		end
	end

	normalizedPayload.action = "Use"
	normalizedPayload.specialAction = skillName

	return self:HandleActionRequest(player, normalizedPayload, skillName)
end

function CriticalService:HandleRequest(player: Player, payload: any): (boolean, string?)
	return self:HandleActionRequest(player, payload, "Critical")
end

return CriticalService
