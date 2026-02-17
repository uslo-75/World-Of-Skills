local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local HitService = require(game.ServerStorage.Module.HitService)

local MIN_START_VY = -40
local LANDING_VY = -2
local RAY_LENGTH = 4
local UPDATE_INTERVAL = 1 / 30

local MIN_LAND_FALL = 10
local MIN_DAMAGE = 2

local fallParams = RaycastParams.new()
fallParams.FilterType = Enum.RaycastFilterType.Exclude
fallParams.IgnoreWater = false
fallParams.RespectCanCollide = true

local fallData = setmetatable({}, { __mode = "k" }) -- [char] = { falling: boolean, oldY: number, fallMag: number }
local updateAccumulator = 0

local function getBucket(char: Model)
	local b = fallData[char]
	if not b then
		b = { falling = false, oldY = 0, fallMag = 0 }
		fallData[char] = b
	end
	return b
end

local function refreshParams(char: Model)
	fallParams.FilterDescendantsInstances = { char }
end

local function computeDamage(fallMag: number): number
	-- same formula as client (Actions.UpdateFall)
	return ((fallMag - 20) * 1.5) * 0.95
end

RunService.Heartbeat:Connect(function(dt)
	updateAccumulator += dt
	if updateAccumulator < UPDATE_INTERVAL then
		return
	end
	updateAccumulator -= UPDATE_INTERVAL

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char or not char.Parent then
			continue
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			continue
		end
		if humanoid.Health <= 0 then
			continue
		end

		if char:GetAttribute("NoFall") or plr:GetAttribute("Wiped") or CollectionService:HasTag(char, "Dead") then
			local b = fallData[char]
			if b then
				b.falling = false
				b.fallMag = 0
			end
			continue
		end

		refreshParams(char)
		local bucket = getBucket(char)
		local vy = hrp.AssemblyLinearVelocity.Y

		if not bucket.falling then
			if vy < MIN_START_VY then
				bucket.falling = true
				bucket.oldY = hrp.Position.Y
				bucket.fallMag = 0
			end
			continue
		end

		local newY = hrp.Position.Y
		local diff = newY - bucket.oldY
		if diff <= 0 then
			bucket.fallMag -= diff
		end
		bucket.oldY = newY

		if vy <= LANDING_VY then
			continue
		end

		local ray = Workspace:Raycast(hrp.Position, Vector3.new(0, -RAY_LENGTH, 0), fallParams)
		if not (ray and ray.Instance) then
			continue
		end

		local fallMag = bucket.fallMag
		bucket.falling = false
		bucket.fallMag = 0

		if fallMag < MIN_LAND_FALL then
			continue
		end

		local dmg = computeDamage(fallMag)
		if dmg < MIN_DAMAGE then
			continue
		end

		HitService.Hit(humanoid, dmg, false, false, false, 0, false)
	end
end)
