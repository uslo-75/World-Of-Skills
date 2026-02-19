local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M1Calc = require(script.Parent:WaitForChild("M1Calc"))
local M1Anims = require(script.Parent:WaitForChild("M1Anims"))
local M1Constants = require(script.Parent:WaitForChild("M1Constants"))
local CombatNet = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatNet"))

local M1CombatHandler = {}
M1CombatHandler.__index = M1CombatHandler

local function getNumberValue(parent: Instance?, name: string): NumberValue?
	if not parent then
		return nil
	end

	local value = parent:FindFirstChild(name)
	if value and value:IsA("NumberValue") then
		return value
	end

	return nil
end

function M1CombatHandler.new(deps)
	local self = setmetatable({}, M1CombatHandler)

	self.Config = deps.Config
	self.AnimUtil = deps.AnimUtil
	self.AssetsRoot = deps.AssetsRoot
	self.Replication = deps.Replication
	self.StateManager = deps.StateManager
	self.HitboxModule = deps.HitboxModule
	self.GetHitService = deps.GetHitService
	self.MarkInCombat = deps.MarkInCombat
	self.PlayToolSound = deps.PlayToolSound
	self.CombatReplication = deps.CombatReplication
	self.DefenseService = deps.DefenseService
	self.HyperArmorService = deps.HyperArmorService
	self.OnHitResolved = deps.OnHitResolved
	self._autoParryStateByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = { remaining, expiresAt }
	self._autoParryTokenByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = number
	self._autoParryScheduleTokenByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = number

	return self
end

function M1CombatHandler:_setDefenseState(character: Model, isBlocking: boolean, isParrying: boolean)
	if self.DefenseService and typeof(self.DefenseService.SetDefenseStateForCharacter) == "function" then
		self.DefenseService:SetDefenseStateForCharacter(character, isBlocking, isParrying)
		return
	end

	if character and character.Parent then
		character:SetAttribute("isBlocking", isBlocking)
		character:SetAttribute("Parrying", isParrying)
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player and self.StateManager and typeof(self.StateManager.SetState) == "function" then
		self.StateManager.SetState(player, "isBlocking", isBlocking)
		self.StateManager.SetState(player, "Parrying", isParrying)
	end
end

function M1CombatHandler:_interruptDefense(character: Model)
	if self.DefenseService and typeof(self.DefenseService.InterruptDefenseCharacter) == "function" then
		self.DefenseService:InterruptDefenseCharacter(character)
		return
	end

	self:_setDefenseState(character, false, false)
end

function M1CombatHandler:_resolvePostureValues(character: Model): (NumberValue?, NumberValue?)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local attributesFolder = player:FindFirstChild("Attributes")
		if attributesFolder and attributesFolder:IsA("Folder") then
			local posture = getNumberValue(attributesFolder, "Posture")
			local maxPosture = getNumberValue(attributesFolder, "MaxPosture")
			if posture and maxPosture then
				return posture, maxPosture
			end
		end
	end

	local characterAttributes = character:FindFirstChild("Attributes")
	if characterAttributes and characterAttributes:IsA("Folder") then
		local posture = getNumberValue(characterAttributes, "Posture")
		local maxPosture = getNumberValue(characterAttributes, "MaxPosture")
		if posture and maxPosture then
			return posture, maxPosture
		end
	end

	return nil, nil
end

function M1CombatHandler:_resolvePosture(character: Model): (number, number)
	local postureValue, maxPostureValue = self:_resolvePostureValues(character)

	local maxPosture = maxPostureValue and maxPostureValue.Value
		or tonumber(character:GetAttribute("MaxPosture"))
		or M1Calc.ToNumber(self.Config.DefaultMaxPosture, 100)
	maxPosture = math.max(1, maxPosture)

	local posture = postureValue and postureValue.Value or tonumber(character:GetAttribute("Posture")) or 0
	posture = math.clamp(posture, 0, maxPosture)

	return posture, maxPosture
end

function M1CombatHandler:_setPosture(character: Model, value: number): (number, number)
	local postureValue, maxPostureValue = self:_resolvePostureValues(character)
	local maxPosture = maxPostureValue and maxPostureValue.Value
		or tonumber(character:GetAttribute("MaxPosture"))
		or M1Calc.ToNumber(self.Config.DefaultMaxPosture, 100)
	maxPosture = math.max(1, maxPosture)

	local clamped = math.clamp(value, 0, maxPosture)
	if postureValue then
		postureValue.Value = clamped
	end

	if not postureValue or character:GetAttribute("Posture") ~= nil then
		character:SetAttribute("Posture", clamped)
	end
	if not maxPostureValue and character:GetAttribute("MaxPosture") == nil then
		character:SetAttribute("MaxPosture", maxPosture)
	end

	return clamped, maxPosture
end

function M1CombatHandler:_addPosture(character: Model, delta: number): (number, number, boolean)
	local current, maxPosture = self:_resolvePosture(character)
	local nextValue = math.clamp(current + delta, 0, maxPosture)
	self:_setPosture(character, nextValue)
	if delta > 0 and nextValue > current then
		character:SetAttribute("PostureLastGainAt", os.clock())
	end

	return nextValue, maxPosture, delta > 0 and nextValue >= maxPosture
end

function M1CombatHandler:_markHitTargetInCombat(attackerPlayer: Player, targetCharacter: Model)
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if not targetPlayer then
		return
	end
	if targetPlayer == attackerPlayer then
		return
	end

	self.MarkInCombat(targetPlayer, targetCharacter)
end

function M1CombatHandler:_replicateGlobalEffect(
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
			"Weaponary",
			effectName,
			payload,
			contextCharacters,
			vfxRadius,
			includePlayers
		)
		return
	end

	self.Replication:FireAllClients("Weaponary", effectName, payload)
end

function M1CombatHandler:ReplicateWeaponaryEffect(
	effectName: string,
	payload: any,
	contextCharacters: { Model }?,
	includePlayers: { Player }?
)
	self:_replicateGlobalEffect(effectName, payload, contextCharacters, includePlayers)
end

function M1CombatHandler:_playToolSound(sourceCharacter: Model?, fallbackToolName: string?, soundNames: any, parent: Instance?)
	if not self.PlayToolSound or typeof(self.PlayToolSound) ~= "function" then
		return
	end

	self.PlayToolSound(sourceCharacter, fallbackToolName, soundNames, parent)
end

function M1CombatHandler:_notifyHitResolved(
	attackerPlayer: Player,
	attackerCharacter: Model,
	targetCharacter: Model,
	outcome: string,
	combo: number,
	hitProfile: { [string]: any }?
)
	if typeof(self.OnHitResolved) ~= "function" then
		return
	end

	task.defer(self.OnHitResolved, attackerPlayer, attackerCharacter, targetCharacter, {
		outcome = outcome,
		combo = combo,
		hitProfile = hitProfile,
	})
end

function M1CombatHandler:_registerParrySuccess(character: Model)
	local serial = tonumber(character:GetAttribute("ParrySuccessSerial")) or 0
	serial = math.max(0, math.floor(serial))
	character:SetAttribute("ParrySuccessSerial", serial + 1)
end

function M1CombatHandler:_setAutoParryActive(character: Model, active: boolean)
	if character and character.Parent then
		character:SetAttribute("AutoParryActive", active)
	end
end

function M1CombatHandler:_clearAutoParry(character: Model, invalidateToken: boolean?)
	self._autoParryStateByCharacter[character] = nil
	self:_setAutoParryActive(character, false)
	self._autoParryScheduleTokenByCharacter[character] = (self._autoParryScheduleTokenByCharacter[character] or 0) + 1

	if invalidateToken then
		self._autoParryTokenByCharacter[character] = (self._autoParryTokenByCharacter[character] or 0) + 1
	end
end

function M1CombatHandler:_resolveAutoParryExpireAt(state): number?
	local expiresAt = state.expiresAt
	local maxGap = M1Calc.ToNumber(self.Config.AutoParryMaxHitGap, 0)
	if maxGap and maxGap > 0 then
		local gapExpireAt = (state.lastAutoParryAt or os.clock()) + maxGap
		if expiresAt then
			expiresAt = math.min(expiresAt, gapExpireAt)
		else
			expiresAt = gapExpireAt
		end
	end

	return expiresAt
end

function M1CombatHandler:_watchAutoParryTimeout(character: Model, token: number)
	if self._autoParryTokenByCharacter[character] ~= token then
		return
	end

	local state = self._autoParryStateByCharacter[character]
	if not state then
		self:_setAutoParryActive(character, false)
		return
	end
	if not character or not character.Parent then
		self:_clearAutoParry(character, true)
		return
	end

	local expireAt = self:_resolveAutoParryExpireAt(state)
	if not expireAt then
		-- Safety: if no timeout config exists, avoid sticky auto-parry state.
		self:_clearAutoParry(character, true)
		return
	end

	local scheduleToken = (self._autoParryScheduleTokenByCharacter[character] or 0) + 1
	self._autoParryScheduleTokenByCharacter[character] = scheduleToken
	local waitTime = math.max(0, expireAt - os.clock())

	task.delay(waitTime, function()
		if self._autoParryTokenByCharacter[character] ~= token then
			return
		end
		if self._autoParryScheduleTokenByCharacter[character] ~= scheduleToken then
			return
		end

		local latestState = self._autoParryStateByCharacter[character]
		if not latestState then
			self:_setAutoParryActive(character, false)
			return
		end
		if not character or not character.Parent then
			self:_clearAutoParry(character, true)
			return
		end

		local latestExpireAt = self:_resolveAutoParryExpireAt(latestState)
		if not latestExpireAt then
			self:_clearAutoParry(character, true)
			return
		end

		if os.clock() >= latestExpireAt then
			self:_clearAutoParry(character, true)
			return
		end

		self:_watchAutoParryTimeout(character, token)
	end)
end

function M1CombatHandler:_activateAutoParry(character: Model)
	local maxHits = math.max(0, math.floor(M1Calc.ToNumber(self.Config.AutoParryMaxHits, 2)))
	local window = M1Calc.ToNumber(self.Config.AutoParryWindow, 0.45)

	if maxHits <= 0 then
		self:_clearAutoParry(character, true)
		return
	end

	local token = (self._autoParryTokenByCharacter[character] or 0) + 1
	self._autoParryTokenByCharacter[character] = token

	local now = os.clock()
	self._autoParryStateByCharacter[character] = {
		remaining = maxHits,
		expiresAt = (window and window > 0) and (now + window) or nil,
		lastAutoParryAt = now,
	}
	self:_setAutoParryActive(character, true)
	self:_watchAutoParryTimeout(character, token)
end

function M1CombatHandler:_consumeAutoParry(character: Model): boolean
	local state = self._autoParryStateByCharacter[character]
	if not state then
		self:_setAutoParryActive(character, false)
		return false
	end
	if not character or not character.Parent then
		self:_clearAutoParry(character, true)
		return false
	end

	if state.remaining <= 0 then
		self:_clearAutoParry(character, true)
		return false
	end

	local now = os.clock()
	local maxGap = M1Calc.ToNumber(self.Config.AutoParryMaxHitGap, 0)
	if maxGap and maxGap > 0 and now - (state.lastAutoParryAt or now) > maxGap then
		self:_clearAutoParry(character, true)
		return false
	end
	if state.expiresAt and os.clock() > state.expiresAt then
		self:_clearAutoParry(character, true)
		return false
	end

	state.remaining -= 1
	state.lastAutoParryAt = now
	if state.remaining <= 0 then
		self:_clearAutoParry(character, true)
	else
		self:_setAutoParryActive(character, true)
		self:_watchAutoParryTimeout(character, self._autoParryTokenByCharacter[character])
	end

	return true
end

function M1CombatHandler:_applyGuardBreak(targetCharacter: Model)
	local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return
	end
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	self:_playToolSound(targetCharacter, nil, { "guardbreak" }, targetRoot)

	self:_clearAutoParry(targetCharacter, true)

	self:_interruptDefense(targetCharacter)
	self:_setPosture(targetCharacter, 0)

	M1Anims.PlayGuardBreak(self.AnimUtil, self.AssetsRoot, targetCharacter, targetHumanoid)

	local stunDuration = math.max(0, M1Calc.ToNumber(self.Config.GuardBreakStun, 2))
	targetCharacter:SetAttribute("GuardBreakUntil", os.clock() + stunDuration)
	if stunDuration > 0 then
		self:_replicateGlobalEffect(
			"SlowStunned",
			CombatNet.MakeCharacterPayload(targetCharacter, {
				Duration = stunDuration,
			}),
			{ targetCharacter },
			{ targetPlayer }
		)
	end
	local hitService = self.GetHitService()
	local usedHitService = false
	if hitService and typeof(hitService.Hit) == "function" and stunDuration > 0 then
		hitService.Hit(targetHumanoid, 0, stunDuration, Vector3.zero, false, 0, false)
		usedHitService = true
	end

	targetCharacter:SetAttribute("SlowStunned", stunDuration > 0)
	if not usedHitService and stunDuration > 0 then
		targetCharacter:SetAttribute("Stunned", true)
		task.delay(stunDuration, function()
			if not targetCharacter.Parent then
				return
			end
			targetCharacter:SetAttribute("Stunned", false)
			targetCharacter:SetAttribute("SlowStunned", false)
		end)
	end
end

function M1CombatHandler:_handleParry(attackerPlayer: Player, attackerCharacter: Model, targetCharacter: Model)
	local isBlocking = targetCharacter:GetAttribute("isBlocking") == true
	self:_setDefenseState(targetCharacter, isBlocking, false)
	self:_registerParrySuccess(targetCharacter)
	self:_activateAutoParry(targetCharacter)
	local defenderPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	self:_replicateGlobalEffect(
		"ParryHit",
		CombatNet.MakeCharacterPayload(targetCharacter),
		{ attackerCharacter, targetCharacter },
		{ attackerPlayer, defenderPlayer }
	)
	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
	self:_playToolSound(targetCharacter, nil, { "parried1", "parried2" }, attackerRoot)

	local defenderPostureRecover = math.max(0, M1Calc.ToNumber(self.Config.PerfectParrySelfPostureRecover, 5))
	if defenderPostureRecover > 0 then
		self:_addPosture(targetCharacter, -defenderPostureRecover)
	end

	local attackerPostureDamage = math.max(0, M1Calc.ToNumber(self.Config.PerfectParryEnemyPostureDamage, 10))
	local _, _, guardBreakAttacker = self:_addPosture(attackerCharacter, attackerPostureDamage)

	M1Anims.PlayParryExchange(self.AnimUtil, self.AssetsRoot, attackerCharacter, targetCharacter)

	local hitService = self.GetHitService()
	local attackerHumanoid = attackerCharacter:FindFirstChildOfClass("Humanoid")
	local defenderHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local attackerStun = math.max(0, M1Calc.ToNumber(self.Config.ParryAttackerStun, 0.5))
	local defenderStun = math.max(0, M1Calc.ToNumber(self.Config.ParryDefenderStun, 0.3))
	if guardBreakAttacker then
		if hitService and typeof(hitService.Hit) == "function" and defenderHumanoid and defenderStun > 0 then
			hitService.Hit(defenderHumanoid, 0, defenderStun, Vector3.zero, false, 0, false)
		end
		self:_applyGuardBreak(attackerCharacter)
		if defenderPlayer then
			self:_markHitTargetInCombat(defenderPlayer, attackerCharacter)
		end
		return
	end

	if hitService and typeof(hitService.Hit) == "function" then
		if attackerHumanoid and attackerStun > 0 then
			hitService.Hit(attackerHumanoid, 0, attackerStun, Vector3.zero, false, 0, false)
		end
		if defenderHumanoid and defenderStun > 0 then
			hitService.Hit(defenderHumanoid, 0, defenderStun, Vector3.zero, false, 0, false)
		end
	end

	if defenderPlayer then
		self:_markHitTargetInCombat(defenderPlayer, attackerCharacter)
	end
end

function M1CombatHandler:_handleAutoParry(attackerPlayer: Player, attackerCharacter: Model, targetCharacter: Model)
	local defenderPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	local attackerHumanoid = attackerCharacter:FindFirstChildOfClass("Humanoid")
	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")

	local postureGain = math.max(0, M1Calc.ToNumber(self.Config.AutoParrySelfPostureGain, 5))
	local _, _, shouldGuardBreakDefender = self:_addPosture(targetCharacter, postureGain)
	self:_replicateGlobalEffect(
		"ParryHit",
		CombatNet.MakeCharacterPayload(targetCharacter),
		{ attackerCharacter, targetCharacter },
		{ attackerPlayer, defenderPlayer }
	)
	self:_playToolSound(targetCharacter, nil, { "parried1", "parried2" }, attackerRoot)

	M1Anims.PlayParryExchange(self.AnimUtil, self.AssetsRoot, attackerCharacter, targetCharacter)

	local hitService = self.GetHitService()
	local attackerStun = math.max(0, M1Calc.ToNumber(self.Config.AutoParryAttackerStun, 0.2))
	if hitService and typeof(hitService.Hit) == "function" and attackerHumanoid and attackerStun > 0 then
		hitService.Hit(attackerHumanoid, 0, attackerStun, Vector3.zero, false, 0, false)
	end

	if shouldGuardBreakDefender then
		self:_applyGuardBreak(targetCharacter)
	end

	if defenderPlayer then
		self:_markHitTargetInCombat(defenderPlayer, attackerCharacter)
	else
		self:_markHitTargetInCombat(attackerPlayer, targetCharacter)
	end
end

function M1CombatHandler:_handleBlock(attackerPlayer: Player, attackerCharacter: Model, targetCharacter: Model, damage: number)
	local defenderPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	local perDamage = math.max(0, M1Calc.ToNumber(self.Config.BlockPosturePerDamage, 4))
	local postureGain = math.max(0, damage) * perDamage
	local _, _, shouldGuardBreak = self:_addPosture(targetCharacter, postureGain)
	self:_replicateGlobalEffect(
		"BlockingHit",
		CombatNet.MakeCharacterPayload(targetCharacter),
		{ attackerCharacter, targetCharacter },
		{ attackerPlayer, defenderPlayer }
	)
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	self:_playToolSound(targetCharacter, nil, { "blocked1", "blocked2" }, targetRoot)

	if shouldGuardBreak then
		self:_applyGuardBreak(targetCharacter)
	end

	self:_markHitTargetInCombat(attackerPlayer, targetCharacter)
end

function M1CombatHandler:ApplyHit(
	attackerPlayer: Player,
	attackerCharacter: Model,
	attackerRoot: BasePart,
	targetCharacter: Model,
	combo: number,
	weaponStats: { [string]: any },
	damage: number,
	attackerToolName: string?,
	hitProfile: { [string]: any }?
)
	if targetCharacter == attackerCharacter then
		return false
	end

	for _, attrName in ipairs(M1Constants.BlockedTargetAttrs) do
		if targetCharacter:GetAttribute(attrName) == true then
			return false
		end
	end

	local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false
	end

	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return false
	end

	local autoParryActive = targetCharacter:GetAttribute("AutoParryActive") == true

	if targetCharacter:GetAttribute("Parrying") == true and not autoParryActive then
		self:_handleParry(attackerPlayer, attackerCharacter, targetCharacter)
		self:_notifyHitResolved(attackerPlayer, attackerCharacter, targetCharacter, "Parried", combo, hitProfile)
		return false
	end
	if self:_consumeAutoParry(targetCharacter) then
		self:_handleAutoParry(attackerPlayer, attackerCharacter, targetCharacter)
		self:_notifyHitResolved(attackerPlayer, attackerCharacter, targetCharacter, "AutoParried", combo, hitProfile)
		return false
	end

	if targetCharacter:GetAttribute("iFrames") == true then
		local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
		self:_replicateGlobalEffect(
			"iFramesSuccess",
			CombatNet.MakeCharacterPayload(targetCharacter),
			{ attackerCharacter, targetCharacter },
			{ attackerPlayer, targetPlayer }
		)
		self:_notifyHitResolved(attackerPlayer, attackerCharacter, targetCharacter, "Dodged", combo, hitProfile)
		return false
	end

	if targetCharacter:GetAttribute("isBlocking") == true and M1Calc.IsBlockingInFront(attackerRoot, targetRoot) then
		local guardBreakOnBlock = typeof(hitProfile) == "table" and hitProfile.guardBreakOnBlock == true
		if guardBreakOnBlock then
			self:_applyGuardBreak(targetCharacter)
			self:_markHitTargetInCombat(attackerPlayer, targetCharacter)
			self:_notifyHitResolved(attackerPlayer, attackerCharacter, targetCharacter, "GuardBreakBlocked", combo, hitProfile)
			return false
		end

		self:_handleBlock(attackerPlayer, attackerCharacter, targetCharacter, damage)
		self:_notifyHitResolved(attackerPlayer, attackerCharacter, targetCharacter, "Blocked", combo, hitProfile)
		return false
	end

	local flatDirection = M1Calc.ResolveFlatDirection(attackerRoot, targetRoot)
	local maxCombo = math.max(1, math.floor(M1Calc.ToNumber(self.Config.MaxCombo, 4)))
	local isLastHit = combo >= maxCombo

	local knockbackStrength = isLastHit and M1Calc.ToNumber(self.Config.FinalKnockback, 30)
		or M1Calc.ToNumber(self.Config.BaseKnockback, 8)
	local stunDuration = isLastHit and M1Calc.ToNumber(self.Config.FinalStun, 1.8) or M1Calc.ToNumber(self.Config.BaseStun, 0.45)
	if typeof(hitProfile) == "table" then
		if hitProfile.knockbackStrength ~= nil then
			knockbackStrength = M1Calc.ToNumber(hitProfile.knockbackStrength, knockbackStrength)
		end
		if hitProfile.stunDuration ~= nil then
			stunDuration = M1Calc.ToNumber(hitProfile.stunDuration, stunDuration)
		end
	end
	local knockback = flatDirection * knockbackStrength

	local ragdoll = isLastHit and self.Config.FinalHitRagdoll == true
	local ragdollDuration = isLastHit and math.max(0, M1Calc.ToNumber(self.Config.FinalHitRagdollDuration, 0)) or 0
	if typeof(hitProfile) == "table" then
		if hitProfile.ragdoll ~= nil then
			ragdoll = hitProfile.ragdoll == true
		end
		if hitProfile.ragdollDuration ~= nil then
			ragdollDuration = math.max(0, M1Calc.ToNumber(hitProfile.ragdollDuration, ragdollDuration))
		end
	end

	local resolvedDamage = damage
	if self.HyperArmorService and typeof(self.HyperArmorService.ResolveIncomingHit) == "function" then
		local armorResult = self.HyperArmorService:ResolveIncomingHit(targetCharacter, resolvedDamage, ragdoll, ragdollDuration)
		if armorResult then
			resolvedDamage = math.max(0, tonumber(armorResult.damage) or 0)
			ragdoll = armorResult.ragdoll == true
			ragdollDuration = math.max(0, tonumber(armorResult.ragdollDuration) or 0)

			if armorResult.blocked == true then
				self:_notifyHitResolved(
					attackerPlayer,
					attackerCharacter,
					targetCharacter,
					"HyperArmorInvulnerable",
					combo,
					hitProfile
				)
				return false
			end
		end
	end

	local hitService = self.GetHitService()
	if hitService and typeof(hitService.Hit) == "function" then
		hitService.Hit(targetHumanoid, resolvedDamage, stunDuration, knockback, ragdoll, ragdollDuration, false, true)
	else
		targetHumanoid:TakeDamage(resolvedDamage)
	end

	local comboForReaction = combo
	if typeof(hitProfile) == "table" and hitProfile.comboForReaction ~= nil then
		comboForReaction = math.max(1, math.floor(M1Calc.ToNumber(hitProfile.comboForReaction, combo)))
	end

	local guardBreakUntil = tonumber(targetCharacter:GetAttribute("GuardBreakUntil")) or 0
	if os.clock() >= guardBreakUntil then
		M1Anims.PlayHitReaction(self.AnimUtil, self.AssetsRoot, targetHumanoid, comboForReaction)
	end
	self:_playToolSound(attackerCharacter, attackerToolName, { "hit1", "hit2" }, attackerRoot)
	targetCharacter:SetAttribute("PlayerTag", attackerPlayer.Name)

	local targetType = "Human"
	local hitEffectName = "Hit"
	if typeof(hitProfile) == "table" then
		if typeof(hitProfile.targetType) == "string" and hitProfile.targetType ~= "" then
			targetType = hitProfile.targetType
		end
		if typeof(hitProfile.effectName) == "string" and hitProfile.effectName ~= "" then
			hitEffectName = hitProfile.effectName
		end
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	self:_replicateGlobalEffect(
		hitEffectName,
		CombatNet.MakeWeaponaryHitPayload(targetCharacter, comboForReaction, targetType),
		{ attackerCharacter, targetCharacter },
		{ attackerPlayer, targetPlayer }
	)

	self:_markHitTargetInCombat(attackerPlayer, targetCharacter)
	self:_notifyHitResolved(attackerPlayer, attackerCharacter, targetCharacter, "Hit", combo, hitProfile)
	return true
end

function M1CombatHandler:SpawnHitbox(
	player: Player,
	character: Model,
	rootPart: BasePart,
	combo: number,
	weaponStats: { [string]: any },
	damage: number,
	attackerToolName: string?,
	hitProfile: { [string]: any }?
)
	if not self.HitboxModule then
		return
	end

	local hitbox = self.HitboxModule.new(player)
	if not hitbox then
		return
	end

	local size = weaponStats.HitboxSize
	if typeof(size) ~= "Vector3" then
		size = Vector3.new(6, 6, 5.5)
	end

	local offset = weaponStats.HitboxOffset
	if typeof(offset) ~= "CFrame" then
		offset = CFrame.new(0, 0, -4)
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
		self:ApplyHit(player, character, rootPart, enemyCharacter, combo, weaponStats, damage, attackerToolName, hitProfile)
	end

	local activeTime = math.max(0.03, M1Calc.ToNumber(self.Config.HitboxActiveTime, 0.08))
	hitbox:Start(activeTime, true)
end

return M1CombatHandler
