local module = {}

module.DefaultInterruptAttrs = table.freeze({
	"Stunned",
	"SlowStunned",
	"IsRagdoll",
	"Downed",
	"Gripped",
	"Gripping",
	"Carried",
	"Carrying",
})

local TRAIL_CACHE_TTL = 0.6
local trailCacheByCharacter = setmetatable({}, { __mode = "k" }) -- [Character] = { [Tool] = { trails, model, expiresAt } }

local function appendTrailUnique(target: { Trail }, seen: { [Trail]: boolean }, trail: Trail)
	if seen[trail] then
		return
	end
	seen[trail] = true
	table.insert(target, trail)
end

local function collectTrailsIn(root: Instance?, target: { Trail }, seen: { [Trail]: boolean })
	if not root then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Trail") then
			appendTrailUnique(target, seen, descendant)
		end
	end
end

local function getCharacterTrailCache(character: Model): { [Tool]: { trails: { Trail }, model: Instance?, expiresAt: number } }
	local cache = trailCacheByCharacter[character]
	if cache then
		return cache
	end

	cache = setmetatable({}, { __mode = "k" })
	trailCacheByCharacter[character] = cache
	return cache
end

function module.CollectWeaponTrails(character: Model, tool: Tool): { Trail }
	if not character or not character.Parent or not tool or not tool.Parent then
		return {}
	end

	local model = character:FindFirstChild(tool.Name .. "Model")
	local now = os.clock()
	local byTool = getCharacterTrailCache(character)
	local cached = byTool[tool]

	if cached and cached.model == model and cached.expiresAt > now then
		local valid = true
		for _, trail in ipairs(cached.trails) do
			if not trail or not trail.Parent then
				valid = false
				break
			end
		end
		if valid then
			return cached.trails
		end
	end

	local trails = {}
	local seen: { [Trail]: boolean } = {}
	collectTrailsIn(tool, trails, seen)
	collectTrailsIn(model, trails, seen)

	byTool[tool] = {
		trails = trails,
		model = model,
		expiresAt = now + TRAIL_CACHE_TTL,
	}

	return trails
end

function module.SetTrailsEnabled(trails: { Trail }, enabled: boolean)
	for _, trail in ipairs(trails) do
		if trail and trail.Parent then
			trail.Enabled = enabled
		end
	end
end

function module.BindInterruptSignals(
	character: Model,
	humanoid: Humanoid?,
	onInterrupted: () -> (),
	interruptAttrs: { string }?
): () -> ()
	local attrs = interruptAttrs or module.DefaultInterruptAttrs
	local conns: { RBXScriptConnection } = {}
	local interrupted = false
	local lastHealth = humanoid and humanoid.Health or nil
	local shouldInterruptImmediately = false

	local function fireInterrupted()
		if interrupted then
			return
		end
		interrupted = true
		onInterrupted()
	end

	for _, attrName in ipairs(attrs) do
		if character:GetAttribute(attrName) == true then
			shouldInterruptImmediately = true
		end

		table.insert(
			conns,
			character:GetAttributeChangedSignal(attrName):Connect(function()
				if character:GetAttribute(attrName) == true then
					fireInterrupted()
				end
			end)
		)
	end

	if humanoid then
		table.insert(
			conns,
			humanoid.HealthChanged:Connect(function(nextHealth)
				local previous = lastHealth
				lastHealth = nextHealth

				if previous ~= nil and nextHealth < previous then
					fireInterrupted()
				end
			end)
		)
	end

	if shouldInterruptImmediately then
		task.defer(fireInterrupted)
	end

	return function()
		for i = #conns, 1, -1 do
			local conn = conns[i]
			if conn and conn.Connected then
				conn:Disconnect()
			end
			conns[i] = nil
		end
	end
end

return table.freeze(module)
