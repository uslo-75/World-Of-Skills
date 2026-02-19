local module = {}

module.DefenseActiveAttrs = table.freeze({
	"isBlocking",
	"Parrying",
	"AutoParryActive",
})

module.DefenseStartBlockedAttrs = table.freeze({
	"Stunned",
	"SlowStunned",
	"IsRagdoll",
	"Downed",
	"Gripped",
	"Gripping",
	"Carried",
	"Carrying",
	"UsingMove",
	"Dashing",
	"Swing",
	"Attacking",
	"AutoParryActive",
	"iFrames",
	"Resting",
})

module.DefenseStartBlockedStates = table.freeze({
	"Dashing",
	"Sliding",
	"Crouching",
	"WallRunning",
	"WallHopping",
	"Climbing",
	"ClimbUp",
	"slidePush",
	"Vaulting",
})

module.DefenseInterruptAttrs = table.freeze({
	"Stunned",
	"SlowStunned",
	"IsRagdoll",
	"Downed",
	"Gripped",
	"Gripping",
	"Carried",
	"Carrying",
	"UsingMove",
	"Dashing",
	"Swing",
	"Attacking",
})

module.DefenseRestoreBlockedAttrs = table.freeze({
	"Stunned",
	"SlowStunned",
	"IsRagdoll",
	"Downed",
	"Swing",
	"Attacking",
})

module.M1BlockedAttrs = table.freeze({
	"Stunned",
	"SlowStunned",
	"IsRagdoll",
	"Downed",
	"Gripped",
	"Gripping",
	"Carried",
	"Carrying",
	"UsingMove",
	"Dashing",
	"isBlocking",
	"Parrying",
	"AutoParryActive",
	"iFrames",
	"Resting",
	"Swing",
	"Attacking",
})

module.M1BlockedStates = table.freeze({
	"Sliding",
	"Dashing",
	"Climbing",
	"Vaulting",
	"WallRunning",
	"WallHopping",
})

module.EquipBlockedAttrs = table.freeze({
	"Stunned",
	"SlowStunned",
	"Parrying",
	"AutoParryActive",
	"Downed",
	"Gripped",
	"Gripping",
	"Carrying",
	"Carried",
})

function module.HasAnyAttribute(character: Model?, attrs: { string }): boolean
	if not character then
		return false
	end

	for _, attrName in ipairs(attrs) do
		if character:GetAttribute(attrName) == true then
			return true
		end
	end

	return false
end

function module.HasAnyState(readState: ((string) -> boolean)?, states: { string }): boolean
	if typeof(readState) ~= "function" then
		return false
	end

	for _, stateName in ipairs(states) do
		if readState(stateName) == true then
			return true
		end
	end

	return false
end

function module.IsDefenseActive(character: Model?): boolean
	return module.HasAnyAttribute(character, module.DefenseActiveAttrs)
end

function module.IsDefenseStartBlocked(character: Model?, readState: ((string) -> boolean)?): boolean
	if module.HasAnyAttribute(character, module.DefenseStartBlockedAttrs) then
		return true
	end

	return module.HasAnyState(readState, module.DefenseStartBlockedStates)
end

function module.IsM1Blocked(character: Model?, readState: ((string) -> boolean)?): boolean
	if module.HasAnyAttribute(character, module.M1BlockedAttrs) then
		return true
	end

	return module.HasAnyState(readState, module.M1BlockedStates)
end

function module.IsEquipBlocked(character: Model?): boolean
	return module.HasAnyAttribute(character, module.EquipBlockedAttrs)
end

return table.freeze(module)
