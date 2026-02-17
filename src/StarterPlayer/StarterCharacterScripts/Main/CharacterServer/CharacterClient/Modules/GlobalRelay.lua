local module = {}
local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer

local GLOBAL_NO_RELAY = {
	FOV = true,
	TweenForward = true,
}

local RELAY_DEDUPE_WINDOW = {
	MomentumSpeed = 0.20,
	BodyTrail = 0.06,
	BodyColour = 0.10,
	Slide = 0.08,
	SlideJump = 0.08,
	SlideJump2 = 0.08,
	WallRun = 0.08,
	Fall = 0.12,
}

local function colorToKey(color: any): string
	if typeof(color) ~= "Color3" then
		return "nil"
	end
	return string.format("%.3f,%.3f,%.3f", color.R, color.G, color.B)
end

local function vectorToKey(vec: any): string
	if typeof(vec) ~= "Vector3" then
		return "nil"
	end
	return string.format("%.3f,%.3f,%.3f", vec.X, vec.Y, vec.Z)
end

local function getPayloadCharacter(payload: any): Model?
	if typeof(payload) ~= "table" then
		return nil
	end

	local char = payload[1] or payload.Char
	if char and typeof(char) == "Instance" and char:IsA("Model") then
		return char
	end

	return nil
end

local function buildRelaySignature(effectName: string, payload: any): string?
	if typeof(payload) ~= "table" then
		return nil
	end

	local char = getPayloadCharacter(payload)
	local charToken = char and tostring(char) or "nil"
	local extra = payload[2]

	if effectName == "MomentumSpeed" then
		local enabled = payload[2]
		return ("%s|%s"):format(charToken, tostring(enabled))
	end

	if effectName == "BodyTrail" then
		local duration = payload[2] or payload.Time
		local location = payload[3] or payload.Location
		return ("%s|%s|%s"):format(charToken, tostring(duration), tostring(location))
	end

	if effectName == "BodyColour" and typeof(extra) == "table" then
		return ("%s|%s|%s"):format(charToken, tostring(extra[1]), colorToKey(extra[2]))
	end

	if effectName == "Slide" and typeof(extra) == "table" then
		return ("%s|%s|%s|%s"):format(charToken, tostring(extra[1]), colorToKey(extra[2]), tostring(extra[3]))
	end

	if effectName == "SlideJump" and typeof(extra) == "table" then
		return ("%s|%s|%s|%s"):format(charToken, tostring(extra[1]), colorToKey(extra[2]), vectorToKey(extra[4]))
	end

	if effectName == "SlideJump2" and typeof(extra) == "table" then
		return ("%s|%s"):format(charToken, colorToKey(extra[1]))
	end

	if effectName == "WallRun" and typeof(extra) == "table" then
		return ("%s|%s|%s"):format(charToken, tostring(extra[1]), tostring(extra[2]))
	end

	if effectName == "Fall" then
		return ("%s|%s"):format(charToken, colorToKey(payload[2]))
	end

	return nil
end

function module.Create(localGlobalModule, replicationRemote)
	local proxyCache: { [string]: any } = {}
	local lastRelayByEffect: { [string]: { sig: string, t: number } } = {}

	local function relayGlobalVfx(effectName: string, params)
		if GLOBAL_NO_RELAY[effectName] then
			return
		end

		local payloadCharacter = getPayloadCharacter(params)
		if payloadCharacter and payloadCharacter ~= LOCAL_PLAYER.Character then
			return
		end

		local dedupeWindow = RELAY_DEDUPE_WINDOW[effectName]
		local signature = buildRelaySignature(effectName, params)
		if dedupeWindow and signature then
			local now = os.clock()
			local prev = lastRelayByEffect[effectName]
			if prev and prev.sig == signature and (now - prev.t) <= dedupeWindow then
				return
			end
			lastRelayByEffect[effectName] = { sig = signature, t = now }
		end

		local ok, err = pcall(function()
			replicationRemote:FireServer("RelayVFX", "Global", effectName, params, { Mode = "Others" })
		end)
		if not ok then
			warn(("[Actions] RelayVFX failed for Global.%s: %s"):format(effectName, tostring(err)))
		end
	end

	return setmetatable({}, {
		__index = function(_, key)
			local fn = localGlobalModule[key]
			if typeof(fn) ~= "function" then
				return fn
			end

			local cached = proxyCache[key]
			if cached then
				return cached
			end

			local wrapped = function(params)
				fn(params)
				relayGlobalVfx(key, params)
			end

			proxyCache[key] = wrapped
			return wrapped
		end,
	})
end

return module
