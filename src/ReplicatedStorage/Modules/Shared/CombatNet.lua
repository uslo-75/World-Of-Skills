local CombatNet = {}

local MOVE_HINT_RUNNING_BIT = 1
local MOVE_HINT_AIRBORNE_BIT = 2

local BLOCK_CODE_BY_ACTION = table.freeze({
	Start = "S",
	Stop = "E",
})

local BLOCK_ACTION_BY_CODE = table.freeze({
	S = "Start",
	E = "Stop",
	s = "Start",
	e = "Stop",
	Start = "Start",
	Stop = "Stop",
	start = "Start",
	stop = "Stop",
})

local CRITICAL_CODE_BY_ACTION = table.freeze({
	Use = "U",
})

local CRITICAL_ACTION_BY_CODE = table.freeze({
	U = "Use",
	u = "Use",
	Use = "Use",
	use = "Use",
})

local SKILL_KEY_CODE_BY_KEY = table.freeze({
	Z = "Z",
	X = "X",
	C = "C",
	V = "V",
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

local function trimString(value: string): string
	return value:match("^%s*(.-)%s*$")
end

function CombatNet.EncodeMoveHint(running: boolean?, airborne: boolean?): number
	local flags = 0
	if running == true then
		flags += MOVE_HINT_RUNNING_BIT
	end
	if airborne == true then
		flags += MOVE_HINT_AIRBORNE_BIT
	end

	return flags
end

function CombatNet.DecodeMoveHint(raw: any): { running: boolean, wasRunning: boolean, airborne: boolean }?
	if raw == nil then
		return nil
	end

	if typeof(raw) == "number" then
		local flags = math.max(0, math.floor(raw))
		local running = (flags % 2) == 1
		local airborne = (math.floor(flags / 2) % 2) == 1

		return {
			running = running,
			wasRunning = running,
			airborne = airborne,
		}
	end

	if typeof(raw) == "table" then
		local running = raw.running == true or raw.wasRunning == true
		local airborne = raw.airborne == true

		return {
			running = running,
			wasRunning = running,
			airborne = airborne,
		}
	end

	return nil
end

function CombatNet.EncodeM1Payload(running: boolean?, airborne: boolean?, toolName: string?): { [any]: any }
	local payload = {
		mh = CombatNet.EncodeMoveHint(running, airborne),
	}

	if typeof(toolName) == "string" then
		local trimmed = trimString(toolName)
		if trimmed ~= "" then
			payload.t = trimmed
		end
	end

	return payload
end

function CombatNet.NormalizeM1Payload(payload: any): ({ [string]: any }?, string?)
	if payload == nil then
		return {}, nil
	end
	if typeof(payload) ~= "table" then
		return nil, "InvalidPayload"
	end

	local normalized = {}

	local toolName = payload.toolName
	if toolName == nil then
		toolName = payload.t
	end

	if toolName ~= nil then
		if typeof(toolName) ~= "string" then
			return nil, "InvalidToolName"
		end

		local trimmed = trimString(toolName)
		if trimmed == "" or #trimmed > 64 then
			return nil, "InvalidToolName"
		end

		normalized.toolName = trimmed
	end

	local rawMoveHint = payload.moveHint
	if rawMoveHint == nil then
		rawMoveHint = payload.mh
	end

	if rawMoveHint ~= nil then
		local decoded = CombatNet.DecodeMoveHint(rawMoveHint)
		if not decoded then
			return nil, "InvalidMoveHint"
		end
		normalized.moveHint = decoded
	end

	return normalized, nil
end

function CombatNet.EncodeBlockAction(action: string): string?
	local normalized = BLOCK_ACTION_BY_CODE[action]
	if not normalized then
		return nil
	end

	return BLOCK_CODE_BY_ACTION[normalized]
end

function CombatNet.NormalizeBlockPayload(payload: any): ({ action: string }?, string?)
	local actionRaw = payload
	if typeof(payload) == "table" then
		actionRaw = payload.action
		if actionRaw == nil then
			actionRaw = payload.a
		end
		if actionRaw == nil then
			actionRaw = payload[1]
		end
	end

	if typeof(actionRaw) == "number" then
		if actionRaw == 1 then
			actionRaw = "Start"
		elseif actionRaw == 0 then
			actionRaw = "Stop"
		end
	end

	if typeof(actionRaw) ~= "string" then
		return nil, "InvalidAction"
	end

	local action = BLOCK_ACTION_BY_CODE[actionRaw]
	if not action then
		return nil, "InvalidAction"
	end

	return { action = action }, nil
end

function CombatNet.EncodeCriticalAction(action: string): string?
	local normalized = CRITICAL_ACTION_BY_CODE[action]
	if not normalized then
		return nil
	end

	return CRITICAL_CODE_BY_ACTION[normalized]
end

function CombatNet.NormalizeCriticalPayload(payload: any): ({ action: string }?, string?)
	local actionRaw = payload
	if typeof(payload) == "table" then
		actionRaw = payload.action
		if actionRaw == nil then
			actionRaw = payload.a
		end
		if actionRaw == nil then
			actionRaw = payload[1]
		end
	end

	if typeof(actionRaw) == "number" and actionRaw == 1 then
		actionRaw = "Use"
	end

	if typeof(actionRaw) ~= "string" then
		return nil, "InvalidAction"
	end

	local action = CRITICAL_ACTION_BY_CODE[actionRaw]
	if not action then
		return nil, "InvalidAction"
	end

	return { action = action }, nil
end

function CombatNet.EncodeSkillPayload(skillKey: string, toolName: string?): { [string]: any }?
	local key = SKILL_KEY_BY_CODE[skillKey]
	if not key then
		return nil
	end

	local payload = {
		k = SKILL_KEY_CODE_BY_KEY[key],
	}

	if typeof(toolName) == "string" then
		local trimmed = trimString(toolName)
		if trimmed ~= "" then
			payload.t = trimmed
		end
	end

	return payload
end

function CombatNet.NormalizeSkillPayload(payload: any): ({ [string]: any }?, string?)
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
	if rawSkillKey == nil then
		rawSkillKey = payload[1]
	end
	if typeof(rawSkillKey) ~= "string" then
		return nil, "InvalidSkillKey"
	end

	local skillKey = SKILL_KEY_BY_CODE[rawSkillKey]
	if not skillKey then
		return nil, "InvalidSkillKey"
	end

	local normalized = {
		skillKey = skillKey,
	}

	local toolName = payload.toolName
	if toolName == nil then
		toolName = payload.t
	end

	if toolName ~= nil then
		if typeof(toolName) ~= "string" then
			return nil, "InvalidToolName"
		end

		local trimmed = trimString(toolName)
		if trimmed == "" or #trimmed > 64 then
			return nil, "InvalidToolName"
		end

		normalized.toolName = trimmed
	end

	return normalized, nil
end

function CombatNet.MakeCharacterPayload(character: Model, value2: any?, value3: any?, value4: any?): { any }
	local payload = { character }
	if value2 ~= nil then
		payload[2] = value2
	end
	if value3 ~= nil then
		payload[3] = value3
	end
	if value4 ~= nil then
		payload[4] = value4
	end

	return payload
end

function CombatNet.MakeIndicatorPayload(character: Model, indicator: string): { any }
	return CombatNet.MakeCharacterPayload(character, indicator)
end

function CombatNet.MakeWeaponaryActionPayload(character: Model, action: string): { any }
	return CombatNet.MakeCharacterPayload(character, action)
end

function CombatNet.MakeWeaponaryHitPayload(character: Model, combo: number, targetType: string): { any }
	return CombatNet.MakeCharacterPayload(character, { combo, targetType })
end

return table.freeze(CombatNet)
