local Players = game:GetService("Players")
local ModifierService = require(script:WaitForChild("ModifierService"))
local StatsService = require(script:WaitForChild("StatsService"))
local RegenService = require(script:WaitForChild("RegenService"))

local RegenManager = {}

RegenManager.Config = {
	MinHealth = 0.1, -- anti-fatal: do not go below this while alive
}

local bound = {}
local function getHumanoid(char)
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function clamp(n, a, b)
	if n < a then
		return a
	end
	if n > b then
		return b
	end
	return n
end

function RegenManager:SetHealth(hum, newHealth)
	if not hum or not hum.Parent then
		return
	end
	hum.Health = clamp(newHealth, 0, hum.MaxHealth)
end

function RegenManager:Heal(hum, amount)
	if not hum or not hum.Parent then
		return
	end
	if amount <= 0 then
		return
	end
	self:SetHealth(hum, hum.Health + amount)
end

-- opts:
--  - allowFatal: boolean (default false) -> if true, can drop to 0
-- Returns: finalHealth
function RegenManager:ApplyDamage(hum, amount, opts)
	opts = opts or {}
	if not hum or not hum.Parent then
		return nil
	end
	if hum.Health <= 0 then
		return hum.Health
	end
	if amount <= 0 then
		return hum.Health
	end

	local newHealth = hum.Health - amount

	if not opts.allowFatal then
		-- anti-fatal: never go below MinHealth
		newHealth = math.max(self.Config.MinHealth, newHealth)
	end

	self:SetHealth(hum, newHealth)

	if typeof(RegenService.MarkDamagedFromHumanoid) == "function" then
		RegenService.MarkDamagedFromHumanoid(hum)
	end

	return hum.Health
end

-- Modifier facade: use buffs directly from RegenManager.
function RegenManager:AddModifier(player: Player, modifierData)
	return ModifierService.AddModifier(player, modifierData)
end

function RegenManager:RemoveModifier(player: Player, modifierId: string): boolean
	return ModifierService.RemoveModifier(player, modifierId)
end

function RegenManager:ClearModifierSource(player: Player, sourceName: string): number
	return ModifierService.ClearSource(player, sourceName)
end

function RegenManager:ClearAllModifiers(player: Player)
	ModifierService.ClearAll(player)
end

function RegenManager:GetModifiers(player: Player, statFilter: string?)
	return ModifierService.GetModifiers(player, statFilter)
end

function RegenManager:HasModifier(player: Player, modifierId: string): boolean
	return ModifierService.HasModifier(player, modifierId)
end

-- Safety net: if another script sets hum.Health below MinHealth (but > 0), restore it.
function RegenManager:BindCharacter(char)
	local hum = getHumanoid(char)
	if not hum then
		hum = char:WaitForChild("Humanoid", 10)
	end
	if not hum then
		return
	end
	if bound[char] then
		return
	end
	bound[char] = true

	local cfg = self.Config
	local changing = false

	hum.HealthChanged:Connect(function(hp)
		if changing then
			return
		end
		if not hum.Parent then
			return
		end

		if hp > 0 and hp < cfg.MinHealth then
			changing = true
			hum.Health = cfg.MinHealth
			changing = false
		end
	end)

	char.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			bound[char] = nil
		end
	end)
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(char)
		RegenManager:BindCharacter(char)
	end)

	if player.Character then
		RegenManager:BindCharacter(player.Character)
	end
end

function RegenManager.Init()
	if RegenManager._initialized then
		return
	end
	RegenManager._initialized = true

	-- Regen stack bootstrap (single entrypoint through RegenManager).
	ModifierService.Init()
	StatsService.Init()
	RegenService.Init()

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)
end

return RegenManager
