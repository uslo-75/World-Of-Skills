local Players = game:GetService("Players")

local module = {}

local buckets: { [Player]: { [string]: { t: number, n: number } } } = {}
local strikes: { [Player]: { score: number, last: number } } = {}

local STRIKE_WINDOW = 10
local KICK_ENABLED = false
local KICK_THRESHOLD = 12

local function getBucket(plr: Player, key: string, window: number)
	local now = os.clock()
	local playerBuckets = buckets[plr]
	if not playerBuckets then
		playerBuckets = {}
		buckets[plr] = playerBuckets
	end

	local bucket = playerBuckets[key]
	if not bucket or (now - bucket.t) > window then
		bucket = { t = now, n = 0 }
	end
	playerBuckets[key] = bucket
	return bucket
end

function module.Allow(plr: Player, key: string, limit: number, window: number): boolean
	local bucket = getBucket(plr, key, window)
	bucket.n += 1
	return bucket.n <= limit
end

function module.Flag(plr: Player, reason: string, severity: number?)
	local now = os.clock()
	local data = strikes[plr]
	if not data or (now - data.last) > STRIKE_WINDOW then
		data = { score = 0, last = now }
	end

	data.score += severity or 1
	data.last = now
	strikes[plr] = data

	plr:SetAttribute("Suspicious", true)
	warn(("[AntiCheat] %s | %s | score=%d"):format(plr.Name, tostring(reason), data.score))

	if KICK_ENABLED and data.score >= KICK_THRESHOLD then
		plr:Kick("Exploit detected")
	end
end

function module.Reset(plr: Player)
	buckets[plr] = nil
	strikes[plr] = nil
end

Players.PlayerRemoving:Connect(function(plr)
	module.Reset(plr)
end)

return module
