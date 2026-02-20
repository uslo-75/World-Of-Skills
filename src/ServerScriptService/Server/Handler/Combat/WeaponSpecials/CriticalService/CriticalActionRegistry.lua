local CriticalConstants = require(script.Parent:WaitForChild("CriticalConstants"))

local ATTR = CriticalConstants.Attributes

local ACTION_DEFS_LIST = {
	table.freeze({
		name = "Critical",
		cooldownAttr = ATTR.Cooldown,
		cooldownTimeAttr = ATTR.CooldownTime,
	}),
	table.freeze({
		name = "Aerial",
		cooldownAttr = "AerialCooldown",
		cooldownTimeAttr = "AerialCooldownTime",
	}),
	table.freeze({
		name = "Running",
		cooldownAttr = "RunningCooldown",
		cooldownTimeAttr = "RunningCooldownTime",
	}),
	table.freeze({
		name = "Strikefall",
		cooldownAttr = "StrikefallCooldown",
		cooldownTimeAttr = "StrikefallCooldownTime",
	}),
	table.freeze({
		name = "RendStep",
		cooldownAttr = "RendStepCooldown",
		cooldownTimeAttr = "RendStepCooldownTime",
	}),
	table.freeze({
		name = "AnchoringStrike",
		cooldownAttr = "AnchoringStrikeCooldown",
		cooldownTimeAttr = "AnchoringStrikeCooldownTime",
	}),
}

local ACTION_DEFS_BY_NAME = {}
for _, actionDef in ipairs(ACTION_DEFS_LIST) do
	ACTION_DEFS_BY_NAME[actionDef.name] = actionDef
end

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

local module = {
	ActionDefsList = table.freeze(ACTION_DEFS_LIST),
	ActionDefsByName = table.freeze(ACTION_DEFS_BY_NAME),
}

function module.NormalizeActionName(raw: any): string
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

function module.ResolveActionDef(actionName: any)
	local normalized = module.NormalizeActionName(actionName)
	return module.ActionDefsByName[normalized], normalized
end

function module.NormalizeSkillKey(raw: any): string?
	if typeof(raw) ~= "string" then
		return nil
	end

	return SKILL_KEY_BY_CODE[raw]
end

return table.freeze(module)
