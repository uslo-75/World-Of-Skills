local Players = game:GetService("Players")

local module = {}

local CLIENT_STATE_ALLOWLIST = {
	Sliding = true,
	Crouching = true,
	WallRunning = true,
	Climbing = true,
}

local CLIENT_REPLICATION_ALLOWLIST = {
	Global = {
		MomentumSpeed = true,
		BodyTrail = true,
		BodyColour = true,
		Slide = true,
		SlideJump = true,
		SlideJump2 = true,
		WallRun = true,
		Fall = true,
	},
}

local RELAY_MODE_ALLOWLIST = {
	All = true,
	Self = true,
	Player = true,
	Others = true,
}

local CLIENT_RELAY_MODE = "Others"
local MAX_TOP_LEVEL_PAYLOAD_KEYS = 8

local RELAY_RATE_BY_CALL = {
	["Global.MomentumSpeed"] = { limit = 10, window = 1 },
	["Global.BodyTrail"] = { limit = 12, window = 1 },
	["Global.BodyColour"] = { limit = 8, window = 1 },
	["Global.Slide"] = { limit = 14, window = 1 },
	["Global.SlideJump"] = { limit = 10, window = 1 },
	["Global.SlideJump2"] = { limit = 10, window = 1 },
	["Global.WallRun"] = { limit = 14, window = 1 },
	["Global.Fall"] = { limit = 8, window = 1 },
}

local relayBuckets: { [Player]: { [string]: { t: number, n: number } } } = {}

local function countKeys(tbl: { [any]: any }): number
	local n = 0
	for _ in pairs(tbl) do
		n += 1
	end
	return n
end

local function getRelayBucket(player: Player, key: string, window: number)
	local now = os.clock()
	local byPlayer = relayBuckets[player]
	if not byPlayer then
		byPlayer = {}
		relayBuckets[player] = byPlayer
	end

	local bucket = byPlayer[key]
	if not bucket or (now - bucket.t) > window then
		bucket = { t = now, n = 0 }
	end
	byPlayer[key] = bucket
	return bucket
end

local function allowRelayCall(player: Player, moduleName: string, functionName: string): boolean
	local relayKey = ("%s.%s"):format(moduleName, functionName)
	local conf = RELAY_RATE_BY_CALL[relayKey]
	if not conf then
		return false
	end

	local bucket = getRelayBucket(player, relayKey, conf.window)
	bucket.n += 1
	return bucket.n <= conf.limit
end

local function isAllowedSlidePart(name: any): boolean
	return name == "Torso"
		or name == "UpperTorso"
		or name == "LowerTorso"
		or name == "Left Arm"
		or name == "Right Arm"
		or name == "Left Leg"
		or name == "Right Leg"
end

local function isAllowedWallRunPart(name: any): boolean
	return name == "Left Arm" or name == "Right Arm"
end

Players.PlayerRemoving:Connect(function(player)
	relayBuckets[player] = nil
end)

function module.IsSafeName(value: any, maxLen: number?): boolean
	if typeof(value) ~= "string" then
		return false
	end

	local limit = maxLen or 32
	if #value == 0 or #value > limit then
		return false
	end

	return true
end

function module.IsAllowedClientState(stateKey: string): boolean
	return CLIENT_STATE_ALLOWLIST[stateKey] == true
end

function module.IsAllowedReplicationCall(moduleName: string, functionName: string): boolean
	local moduleAllowlist = CLIENT_REPLICATION_ALLOWLIST[moduleName]
	if not moduleAllowlist then
		return false
	end
	return moduleAllowlist[functionName] == true
end

function module.IsValidReplicationPayload(
	player: Player,
	moduleName: string,
	functionName: string,
	payload: any
): (boolean, string?)
	if moduleName ~= "Global" then
		return false, "unsupported module"
	end
	if typeof(payload) ~= "table" then
		return false, "payload must be table"
	end
	if countKeys(payload) > MAX_TOP_LEVEL_PAYLOAD_KEYS then
		return false, "payload too large"
	end

	local char = payload[1] or payload.Char
	if not char or char ~= player.Character then
		return false, "payload character mismatch"
	end

	if functionName == "MomentumSpeed" then
		local enabled = payload[2]
		if enabled == nil then
			enabled = payload.Enabled
		end
		if typeof(enabled) ~= "boolean" then
			return false, "MomentumSpeed invalid enabled"
		end
		return true
	end

	if functionName == "BodyTrail" then
		local duration = payload[2] or payload.Time
		local location = payload[3] or payload.Location
		if duration ~= nil and (typeof(duration) ~= "number" or duration <= 0 or duration > 2) then
			return false, "BodyTrail invalid duration"
		end
		if location ~= nil and (typeof(location) ~= "string" or #location == 0 or #location > 24) then
			return false, "BodyTrail invalid location"
		end
		return true
	end

	if functionName == "BodyColour" then
		local data = payload[2]
		if typeof(data) ~= "table" then
			return false, "BodyColour invalid data"
		end
		local duration = data[1]
		local color = data[2]
		if typeof(duration) ~= "number" or duration <= 0 or duration > 5 then
			return false, "BodyColour invalid duration"
		end
		if typeof(color) ~= "Color3" then
			return false, "BodyColour invalid color"
		end
		return true
	end

	if functionName == "Slide" then
		local extra = payload[2]
		if typeof(extra) ~= "table" then
			return false, "Slide invalid extra"
		end
		if not isAllowedSlidePart(extra[1]) then
			return false, "Slide invalid limb"
		end
		if extra[2] ~= nil and typeof(extra[2]) ~= "Color3" then
			return false, "Slide invalid ground color"
		end
		if typeof(extra[3]) ~= "boolean" then
			return false, "Slide invalid enabled"
		end
		return true
	end

	if functionName == "SlideJump" then
		local extra = payload[2]
		if extra ~= nil and typeof(extra) ~= "table" then
			return false, "SlideJump invalid extra"
		end
		if extra then
			if extra[2] ~= nil and typeof(extra[2]) ~= "Color3" then
				return false, "SlideJump invalid ground color"
			end
			if extra[4] ~= nil and typeof(extra[4]) ~= "Vector3" then
				return false, "SlideJump invalid ground normal"
			end
		end
		return true
	end

	if functionName == "SlideJump2" then
		local extra = payload[2]
		if extra ~= nil and typeof(extra) ~= "table" then
			return false, "SlideJump2 invalid extra"
		end
		if extra and extra[1] ~= nil and typeof(extra[1]) ~= "Color3" then
			return false, "SlideJump2 invalid ground color"
		end
		return true
	end

	if functionName == "WallRun" then
		local extra = payload[2]
		if typeof(extra) ~= "table" then
			return false, "WallRun invalid extra"
		end
		if not isAllowedWallRunPart(extra[1]) then
			return false, "WallRun invalid limb"
		end
		if typeof(extra[2]) ~= "boolean" then
			return false, "WallRun invalid enabled"
		end
		return true
	end

	if functionName == "Fall" then
		local extra = payload[2]
		if extra ~= nil and typeof(extra) ~= "Color3" then
			return false, "Fall invalid color"
		end
		return true
	end

	return false, "unsupported function"
end

function module.ResolveRelayOptions(options: any): (string, number?)
	local mode = "Others"
	local targetUserId = nil

	if typeof(options) == "table" then
		if typeof(options.Mode) == "string" and RELAY_MODE_ALLOWLIST[options.Mode] then
			mode = options.Mode
		end
		if typeof(options.TargetUserId) == "number" then
			targetUserId = options.TargetUserId
		end
	elseif typeof(options) == "string" and RELAY_MODE_ALLOWLIST[options] then
		mode = options
	end

	return mode, targetUserId
end

function module.RelayReplicationEvent(
	replicationRemote: RemoteEvent,
	sourcePlayer: Player,
	moduleName: string,
	functionName: string,
	payload: any,
	options: any
)
	local mode, targetUserId = module.ResolveRelayOptions(options)

	if mode == "All" then
		replicationRemote:FireAllClients(moduleName, functionName, payload)
		return
	end

	if mode == "Self" then
		replicationRemote:FireClient(sourcePlayer, moduleName, functionName, payload)
		return
	end

	if mode == "Player" and targetUserId ~= nil then
		local target = Players:GetPlayerByUserId(targetUserId)
		if target then
			replicationRemote:FireClient(target, moduleName, functionName, payload)
		end
		return
	end

	for _, target in ipairs(Players:GetPlayers()) do
		if target ~= sourcePlayer then
			replicationRemote:FireClient(target, moduleName, functionName, payload)
		end
	end
end

function module.HandleReplicationRelay(
	antiCheat: any,
	replicationRemote: RemoteEvent,
	player: Player,
	moduleName: any,
	functionName: any,
	payload: any,
	options: any
): boolean
	if not antiCheat.Allow(player, "ReplicationRelay", 25, 1) then
		antiCheat.Flag(player, "ReplicationRelay rate-limit", 1)
		return false
	end

	if not module.IsSafeName(moduleName, 32) or not module.IsSafeName(functionName, 32) then
		antiCheat.Flag(player, "ReplicationRelay invalid names", 1)
		return false
	end

	if not module.IsAllowedReplicationCall(moduleName, functionName) then
		antiCheat.Flag(player, ("ReplicationRelay blocked: %s.%s"):format(moduleName, functionName), 1)
		return false
	end

	local mode = module.ResolveRelayOptions(options)
	if mode ~= CLIENT_RELAY_MODE then
		antiCheat.Flag(player, "ReplicationRelay invalid mode", 1)
		return false
	end

	if not allowRelayCall(player, moduleName, functionName) then
		antiCheat.Flag(player, ("ReplicationRelay per-call rate-limit: %s.%s"):format(moduleName, functionName), 1)
		return false
	end

	local okPayload, payloadErr = module.IsValidReplicationPayload(player, moduleName, functionName, payload)
	if not okPayload then
		antiCheat.Flag(player, ("ReplicationRelay invalid payload: %s"):format(tostring(payloadErr)), 1)
		return false
	end

	module.RelayReplicationEvent(replicationRemote, player, moduleName, functionName, payload, CLIENT_RELAY_MODE)
	return true
end

function module.GetDashConfig(): { cooldown: number, duration: number }
	local dash = { cooldown = 1.5, duration = 0.25 }
	local sp = game:FindFirstChild("StarterPlayer")
	if not sp then
		return dash
	end

	local scs = sp:FindFirstChild("StarterCharacterScripts")
	local main = scs and scs:FindFirstChild("Main")
	local cs = main and main:FindFirstChild("CharacterServer")
	local cc = cs and cs:FindFirstChild("CharacterClient")
	local mods = cc and cc:FindFirstChild("Modules")
	local settingsMod = mods and mods:FindFirstChild("Settings")

	if settingsMod and settingsMod:IsA("ModuleScript") then
		local ok, settings = pcall(require, settingsMod)
		if ok and settings and settings.Dash then
			local dur = tonumber(settings.Dash.Duration) or dash.duration
			local cancelDur = tonumber(settings.Dash.CancelDur) or dur
			dash.duration = math.max(dur, cancelDur)
			dash.cooldown = tonumber(settings.Dash.Cooldown) or dash.cooldown
		end
	end

	return dash
end

return module
