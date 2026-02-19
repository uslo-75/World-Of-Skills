local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatNet = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatNet"))

local HyperArmorService = {}
HyperArmorService.__index = HyperArmorService

local ATTR_TYPE = "HyperArmorType"
local ATTR_EXPIRES_AT = "HyperArmorExpiresAt"
local ATTR_DAMAGE_MULT = "HyperArmorDamageMultiplier"
local ATTR_NO_RAGDOLL = "HyperArmorNoRagdoll"
local ATTR_SOURCE = "HyperArmorSource"

local TYPE_INVULNERABLE = "Invulnerable"
local TYPE_RESILIENT = "Resilient"

local DEFAULT_SETTINGS = table.freeze({
	VfxReplicationRadius = 180,
	DefaultResilientMultiplier = 0.45,
	DefaultInvulnerableDuration = 1,
	DefaultResilientDuration = 0.7,
})

local function mergeSettings(raw: { [string]: any }?): { [string]: any }
	local merged = {}
	for key, value in pairs(DEFAULT_SETTINGS) do
		merged[key] = value
	end

	if typeof(raw) == "table" then
		for key, value in pairs(raw) do
			merged[key] = value
		end
	end

	return merged
end

local function normalizeType(raw: any): string?
	if typeof(raw) ~= "string" then
		return nil
	end

	local key = string.lower(raw)
	if key == "invulnerable" or key == "fulliframe" or key == "iframe" or key == "full_iframe" then
		return TYPE_INVULNERABLE
	end
	if key == "resilient" or key == "hyperarmor" or key == "hyper_armor" or key == "hyper" then
		return TYPE_RESILIENT
	end

	return nil
end

function HyperArmorService.new(deps: { [string]: any }?)
	local dependencies = deps or {}
	local self = setmetatable({}, HyperArmorService)

	self.Settings = mergeSettings(dependencies.Settings)
	self.Replication = dependencies.Replication
	self.CombatReplication = dependencies.CombatReplication

	self._tokenByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = number

	return self
end

function HyperArmorService:_isCharacterValid(character: Model?): boolean
	return character ~= nil and character.Parent ~= nil
end

function HyperArmorService:_replicate(
	character: Model,
	actionName: string,
	armorType: string?,
	duration: number?,
	includePlayers: { Player }?
)
	if not self.Replication then
		return
	end

	local payloadData = {
		Action = actionName,
	}
	if typeof(armorType) == "string" and armorType ~= "" then
		payloadData.Type = armorType
	end
	if typeof(duration) == "number" then
		payloadData.Duration = math.max(0, duration)
	end

	local payload = CombatNet.MakeCharacterPayload(character, payloadData)
	local radius = math.max(0, tonumber(self.Settings.VfxReplicationRadius) or 180)

	if self.CombatReplication and typeof(self.CombatReplication.FireClientsNear) == "function" then
		self.CombatReplication.FireClientsNear(
			self.Replication,
			"Weaponary",
			"HyperArmor",
			payload,
			{ character },
			radius,
			includePlayers
		)
		return
	end

	self.Replication:FireAllClients("Weaponary", "HyperArmor", payload)
end

function HyperArmorService:_clearAttributes(character: Model)
	character:SetAttribute(ATTR_TYPE, nil)
	character:SetAttribute(ATTR_EXPIRES_AT, nil)
	character:SetAttribute(ATTR_DAMAGE_MULT, nil)
	character:SetAttribute(ATTR_NO_RAGDOLL, nil)
	character:SetAttribute(ATTR_SOURCE, nil)
end

function HyperArmorService:_isExpired(character: Model): boolean
	local expiresAt = tonumber(character:GetAttribute(ATTR_EXPIRES_AT)) or 0
	return expiresAt > 0 and os.clock() >= expiresAt
end

function HyperArmorService:GetState(character: Model?): { [string]: any }?
	if not self:_isCharacterValid(character) then
		return nil
	end

	local armorType = character:GetAttribute(ATTR_TYPE)
	if typeof(armorType) ~= "string" or armorType == "" then
		return nil
	end

	if self:_isExpired(character) then
		self:Clear(character, nil, { replicate = true })
		return nil
	end

	return {
		type = armorType,
		expiresAt = tonumber(character:GetAttribute(ATTR_EXPIRES_AT)) or 0,
		damageMultiplier = math.clamp(tonumber(character:GetAttribute(ATTR_DAMAGE_MULT)) or 1, 0, 1),
		noRagdoll = character:GetAttribute(ATTR_NO_RAGDOLL) == true,
		source = character:GetAttribute(ATTR_SOURCE),
	}
end

function HyperArmorService:IsActive(character: Model?): boolean
	return self:GetState(character) ~= nil
end

function HyperArmorService:Apply(character: Model, options: { [string]: any }?): boolean
	if not self:_isCharacterValid(character) then
		return false
	end

	local opts = options or {}
	local armorType = normalizeType(opts.type or opts.armorType) or TYPE_RESILIENT
	local defaultDuration = armorType == TYPE_INVULNERABLE and self.Settings.DefaultInvulnerableDuration
		or self.Settings.DefaultResilientDuration
	local duration = math.max(0.05, tonumber(opts.duration) or defaultDuration)
	local expiresAt = os.clock() + duration
	local source = opts.source
	local includePlayers = opts.includePlayers
	local replicate = (opts.replicate ~= false)

	local token = (self._tokenByCharacter[character] or 0) + 1
	self._tokenByCharacter[character] = token

	local damageMultiplier = tonumber(opts.damageMultiplier)
	if armorType == TYPE_INVULNERABLE then
		damageMultiplier = 0
	else
		damageMultiplier = math.clamp(
			damageMultiplier or tonumber(self.Settings.DefaultResilientMultiplier) or 0.45,
			0,
			1
		)
	end

	local noRagdoll = opts.noRagdoll
	if noRagdoll == nil then
		noRagdoll = true
	end

	character:SetAttribute(ATTR_TYPE, armorType)
	character:SetAttribute(ATTR_EXPIRES_AT, expiresAt)
	character:SetAttribute(ATTR_DAMAGE_MULT, damageMultiplier)
	character:SetAttribute(ATTR_NO_RAGDOLL, noRagdoll == true)
	character:SetAttribute(ATTR_SOURCE, typeof(source) == "string" and source or nil)

	if replicate then
		self:_replicate(character, "Start", armorType, duration, includePlayers)
	end

	task.delay(duration, function()
		if self._tokenByCharacter[character] ~= token then
			return
		end
		self:Clear(character, source, { replicate = replicate, includePlayers = includePlayers })
	end)

	return true
end

function HyperArmorService:Clear(character: Model?, expectedSource: any?, options: { [string]: any }?): boolean
	if not self:_isCharacterValid(character) then
		return false
	end

	local opts = options or {}
	local currentType = character:GetAttribute(ATTR_TYPE)
	if typeof(currentType) ~= "string" or currentType == "" then
		return false
	end

	if typeof(expectedSource) == "string" and expectedSource ~= "" then
		local currentSource = character:GetAttribute(ATTR_SOURCE)
		if typeof(currentSource) == "string" and currentSource ~= expectedSource then
			return false
		end
	end

	self._tokenByCharacter[character] = (self._tokenByCharacter[character] or 0) + 1
	self:_clearAttributes(character)

	if opts.replicate ~= false then
		self:_replicate(character, "Stop", currentType, nil, opts.includePlayers)
	end

	return true
end

function HyperArmorService:ResolveIncomingHit(
	character: Model?,
	incomingDamage: number,
	ragdoll: boolean,
	ragdollDuration: number
): { [string]: any }?
	local state = self:GetState(character)
	if not state then
		return nil
	end

	if state.type == TYPE_INVULNERABLE then
		if character then
			self:_replicate(character, "Impact", TYPE_INVULNERABLE, nil, nil)
		end
		return {
			blocked = true,
			type = TYPE_INVULNERABLE,
			damage = 0,
			ragdoll = false,
			ragdollDuration = 0,
		}
	end

	local damageMultiplier = math.clamp(state.damageMultiplier, 0, 1)
	local adjustedDamage = math.max(0, tonumber(incomingDamage) or 0) * damageMultiplier
	local adjustedRagdoll = ragdoll
	local adjustedRagdollDuration = ragdollDuration
	if state.noRagdoll then
		adjustedRagdoll = false
		adjustedRagdollDuration = 0
	end

	if character then
		self:_replicate(character, "Impact", TYPE_RESILIENT, nil, nil)
	end

	return {
		blocked = false,
		type = TYPE_RESILIENT,
		damage = adjustedDamage,
		ragdoll = adjustedRagdoll,
		ragdollDuration = adjustedRagdollDuration,
	}
end

return HyperArmorService
